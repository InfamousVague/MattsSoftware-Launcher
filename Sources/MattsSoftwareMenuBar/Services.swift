import AppKit
import Foundation

/// All the native side-effects: installed-version probe, GitHub
/// latest-release lookup, and the DMG install pipeline (download →
/// hdiutil attach → ditto → detach). Pure Foundation/AppKit, no
/// third-party anything.
enum Services {

    // MARK: Process helper

    @discardableResult
    static func run(
        _ launchPath: String,
        _ args: [String]
    ) -> (ok: Bool, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let o = Pipe(), e = Pipe()
        p.standardOutput = o
        p.standardError = e
        do {
            try p.run()
        } catch {
            return (false, "", "\(error)")
        }
        let od = o.fileHandleForReading.readDataToEndOfFile()
        let ed = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (
            p.terminationStatus == 0,
            String(decoding: od, as: UTF8.self),
            String(decoding: ed, as: UTF8.self)
        )
    }

    // MARK: Installed detection

    static func appBundlePath(_ bundleName: String) -> String {
        "/Applications/\(bundleName).app"
    }

    /// `CFBundleShortVersionString` from the installed bundle, or
    /// nil if it isn't in /Applications. Empty string = present but
    /// version-unknown.
    static func installedVersion(_ bundleName: String) -> String? {
        let path = appBundlePath(bundleName)
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        if let b = Bundle(path: path),
           let v = b.infoDictionary?["CFBundleShortVersionString"]
               as? String,
           !v.isEmpty {
            return v
        }
        return ""
    }

    // MARK: GitHub latest release

    struct Release {
        let tag: String
        let dmg: String?
    }

    static func githubLatest(_ repo: String) async throws -> Release {
        let full = repo.contains("/") ? repo : "\(GITHUB_OWNER)/\(repo)"
        guard
            let url = URL(
                string:
                    "https://api.github.com/repos/\(full)/releases/latest"
            )
        else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue(
            "MattsSoftware-MenuBar", forHTTPHeaderField: "User-Agent")
        req.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            let code =
                (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(
                domain: "github", code: code,
                userInfo: [
                    NSLocalizedDescriptionKey: "GitHub API \(code)"
                ])
        }
        let json =
            try JSONSerialization.jsonObject(with: data)
            as? [String: Any] ?? [:]
        let tag = json["tag_name"] as? String ?? ""
        var dmg: String?
        if let assets = json["assets"] as? [[String: Any]] {
            for a in assets {
                if let n = a["name"] as? String,
                   n.lowercased().hasSuffix(".dmg"),
                   let u = a["browser_download_url"] as? String {
                    dmg = u
                    break
                }
            }
        }
        return Release(tag: tag, dmg: dmg)
    }

    /// Loose "is it different" check — any difference surfaces an
    /// Update (avoids mis-ranking a non-semver tag into a false
    /// up-to-date).
    static func norm(_ v: String) -> String {
        var s = v.trimmingCharacters(in: .whitespaces)
        while s.hasPrefix("v") || s.hasPrefix("V") {
            s.removeFirst()
        }
        return s
    }

    static func resolveStatus(_ app: CatalogApp) async -> AppStatus {
        var st = AppStatus()
        if let bn = app.bundleName {
            st.installedVersion = installedVersion(bn)
            st.installed = st.installedVersion != nil
        }
        switch app.channel {
        case .github:
            if let repo = app.githubRepo {
                do {
                    let r = try await githubLatest(repo)
                    if !r.tag.isEmpty { st.latestVersion = r.tag }
                    st.downloadURL = r.dmg
                } catch {
                    st.error = error.localizedDescription
                }
            }
        case .dmg:
            st.downloadURL = app.url
        case .appstore, .library:
            break
        }
        if let iv = st.installedVersion, !iv.isEmpty,
           let lv = st.latestVersion {
            st.updatable = norm(iv) != norm(lv)
        }
        return st
    }

    // MARK: Install pipeline

    enum InstallError: LocalizedError {
        case download(String)
        case mount(String)
        case noApp
        case copy(String)
        var errorDescription: String? {
            switch self {
            case .download(let s): return "Download failed: \(s)"
            case .mount(let s): return "Mount failed: \(s)"
            case .noApp: return "No .app found in the disk image"
            case .copy(let s): return "Copy failed: \(s)"
            }
        }
    }

    /// Download → attach → ditto into /Applications → detach.
    /// `phase` is called with a short human status for the menu UI.
    static func installApp(
        _ app: CatalogApp,
        downloadURL: String,
        phase: @escaping (String) -> Void
    ) async throws -> String {
        phase("Downloading…")
        guard let url = URL(string: downloadURL) else {
            throw InstallError.download("bad URL")
        }
        var req = URLRequest(url: url)
        req.setValue(
            "MattsSoftware-MenuBar", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 600
        let tmp: URL
        do {
            let (file, _) = try await URLSession.shared.download(
                for: req)
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "mattssoftware-\(app.id)-\(getpid()).dmg")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: file, to: dest)
            tmp = dest
        } catch {
            throw InstallError.download(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: tmp) }

        phase("Mounting…")
        let attach = run(
            "/usr/bin/hdiutil",
            [
                "attach", "-nobrowse", "-noverify", "-quiet",
                tmp.path, "-mountrandom", "/tmp",
            ])
        guard attach.ok else {
            throw InstallError.mount(attach.err)
        }
        // Mountpoint = last whitespace/tab token that's an abs path.
        var mount: String?
        for line in attach.out.split(separator: "\n") {
            if let last = line.split(whereSeparator: { $0 == "\t" })
                .last?
                .trimmingCharacters(in: .whitespaces),
                last.hasPrefix("/") {
                mount = last
            }
        }
        guard let mountPoint = mount else {
            throw InstallError.mount("could not parse mountpoint")
        }
        defer {
            run(
                "/usr/bin/hdiutil",
                ["detach", "-quiet", "-force", mountPoint])
        }

        phase("Copying…")
        let fm = FileManager.default
        guard
            let entries = try? fm.contentsOfDirectory(
                atPath: mountPoint),
            let appName = entries.first(where: {
                $0.hasSuffix(".app")
            })
        else { throw InstallError.noApp }
        let src = "\(mountPoint)/\(appName)"
        let dst = "/Applications/\(appName)"
        if fm.fileExists(atPath: dst) {
            try? fm.removeItem(atPath: dst)
        }
        let cp = run("/usr/bin/ditto", [src, dst])
        guard cp.ok else { throw InstallError.copy(cp.err) }
        phase("Installed")
        return dst
    }

    // MARK: Open / external

    static func openApp(_ bundleName: String) {
        let url = URL(
            fileURLWithPath: appBundlePath(bundleName))
        NSWorkspace.shared.open(url)
    }

    static func openExternal(_ s: String) {
        if let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }

    // MARK: Bundled icons

    /// Real squircle icon for a catalog row, loaded from the
    /// SwiftPM resource bundle. Cached so scrolling the list
    /// doesn't re-decode.
    private static var iconCache: [String: NSImage] = [:]

    static func appIcon(_ asset: String) -> NSImage? {
        if let hit = iconCache[asset] { return hit }
        guard
            let url = Bundle.module.url(
                forResource: asset, withExtension: "png"),
            let img = NSImage(contentsOf: url)
        else { return nil }
        iconCache[asset] = img
        return img
    }

    /// MattsSoftware brand mark for the popover header.
    static let brandIcon: NSImage? = appIcon("launcher")
}

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
    ///
    /// IMPORTANT: read `Contents/Info.plist` straight off disk every
    /// call. `Bundle(path:)` is cached by Foundation per path for
    /// the process lifetime — after an in-place update (ditto over
    /// /Applications/X.app) it keeps reporting the *old* version, so
    /// the row stayed on "Update" until the launcher was relaunched
    /// (fresh installs looked fine only because nothing was cached
    /// for that path yet). A fresh plist read fixes update detection
    /// without needing a manual refresh / relaunch.
    static func installedVersion(_ bundleName: String) -> String? {
        let path = appBundlePath(bundleName)
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        let plist = "\(path)/Contents/Info.plist"
        if let dict = NSDictionary(contentsOfFile: plist),
           let v = dict["CFBundleShortVersionString"] as? String,
           !v.isEmpty {
            return v
        }
        // Fallback for the rare bundle whose Info.plist isn't at the
        // standard path — still avoids the cached Bundle by parsing
        // a fresh instance only as a last resort.
        if let data = FileManager.default.contents(atPath: plist),
           let obj = try? PropertyListSerialization.propertyList(
               from: data, options: [], format: nil),
           let d = obj as? [String: Any],
           let v = d["CFBundleShortVersionString"] as? String,
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

    /// Optional PAT to lift the unauthenticated 60-req/hr limit to
    /// 5000/hr. Zero-config: env `GITHUB_TOKEN`, else a one-line
    /// `~/.config/mattssoftware/github-token` file. Absent is fine —
    /// the cache + conditional requests keep us well under 60/hr.
    private static func githubToken() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let t = env["GITHUB_TOKEN"], !t.isEmpty { return t }
        if let t = env["MS_GITHUB_TOKEN"], !t.isEmpty { return t }
        let p = ("~/.config/mattssoftware/github-token" as NSString)
            .expandingTildeInPath
        if let s = try? String(contentsOfFile: p, encoding: .utf8) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return nil
    }

    /// Skip the network entirely when the cached entry is younger
    /// than this — the dominant fix for the 403s (one popover-warm
    /// was firing 12 fresh requests; a few opens drained 60/hr).
    private static let releaseTTL: TimeInterval = 15 * 60

    /// Latest release for `repo`, rate-limit-hardened:
    ///  • fresh cache (< TTL) → no request at all
    ///  • else conditional `If-None-Match`; a 304 is free vs the
    ///    GitHub rate limit and just refreshes the cache stamp
    ///  • 403 / network error → serve last-known-good (even stale)
    ///    so the row keeps showing its version + Update instead of
    ///    "Couldn't check GitHub"
    ///  • only throws when rate-limited/offline AND nothing cached
    static func githubLatest(_ repo: String) async throws -> Release {
        let full =
            repo.contains("/") ? repo : "\(GITHUB_OWNER)/\(repo)"
        let cached = await ReleaseCache.shared.get(full)
        if let c = cached,
           Date().timeIntervalSince(c.fetchedAt) < releaseTTL {
            return Release(tag: c.tag, dmg: c.dmg)
        }
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
        if let tok = githubToken() {
            req.setValue(
                "Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        if let etag = cached?.etag {
            req.setValue(
                etag, forHTTPHeaderField: "If-None-Match")
        }
        req.timeoutInterval = 15

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            if let c = cached { return Release(tag: c.tag, dmg: c.dmg) }
            throw error
        }
        guard let http = resp as? HTTPURLResponse else {
            if let c = cached { return Release(tag: c.tag, dmg: c.dmg) }
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 304, let c = cached {
            await ReleaseCache.shared.set(
                full,
                .init(
                    tag: c.tag, dmg: c.dmg, etag: c.etag,
                    fetchedAt: Date()))
            return Release(tag: c.tag, dmg: c.dmg)
        }

        if (200..<300).contains(http.statusCode) {
            let json =
                (try? JSONSerialization.jsonObject(with: data))
                as? [String: Any] ?? [:]
            var tag = json["tag_name"] as? String ?? ""
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
            // The newest release may be a stray/assetless tag (no CI
            // build). Don't degrade to the releases page — fall back to
            // the newest release that actually ships a .dmg.
            if dmg == nil, let fb = await firstDmgRelease(full) {
                tag = fb.0
                dmg = fb.1
            }
            await ReleaseCache.shared.set(
                full,
                .init(
                    tag: tag, dmg: dmg,
                    etag: http.value(forHTTPHeaderField: "Etag"),
                    fetchedAt: Date()))
            return Release(tag: tag, dmg: dmg)
        }

        // Rate-limited / not-found / 5xx: stale cache beats nothing.
        if let c = cached { return Release(tag: c.tag, dmg: c.dmg) }
        let msg =
            http.statusCode == 403
            ? "GitHub rate-limited — retry shortly (or set GITHUB_TOKEN)"
            : "GitHub API \(http.statusCode)"
        throw NSError(
            domain: "github", code: http.statusCode,
            userInfo: [NSLocalizedDescriptionKey: msg])
    }

    /// Best-effort: newest non-draft release that actually has a .dmg.
    /// Used only when `releases/latest` is assetless, so a stray tag
    /// can't break Download.
    private static func firstDmgRelease(
        _ full: String
    ) async -> (String, String)? {
        guard
            let url = URL(
                string:
                    "https://api.github.com/repos/\(full)/releases?per_page=20"
            )
        else { return nil }
        var req = URLRequest(url: url)
        req.setValue(
            "MattsSoftware-MenuBar", forHTTPHeaderField: "User-Agent")
        req.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept")
        if let tok = githubToken() {
            req.setValue(
                "Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        req.timeoutInterval = 15
        guard
            let (data, resp) = try? await URLSession.shared.data(
                for: req),
            let http = resp as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            let arr =
                (try? JSONSerialization.jsonObject(with: data))
                as? [[String: Any]]
        else { return nil }
        for rel in arr {
            if (rel["draft"] as? Bool) == true { continue }
            let tag = rel["tag_name"] as? String ?? ""
            if let assets = rel["assets"] as? [[String: Any]] {
                for a in assets {
                    if let n = a["name"] as? String,
                       n.lowercased().hasSuffix(".dmg"),
                       let u = a["browser_download_url"] as? String {
                        return (tag, u)
                    }
                }
            }
        }
        return nil
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

    /// Download the dmg to a temp file (caller owns/deletes it).
    private static func downloadDMG(
        _ downloadURL: String, id: String
    ) async throws -> URL {
        guard let url = URL(string: downloadURL) else {
            throw InstallError.download("bad URL")
        }
        var req = URLRequest(url: url)
        req.setValue(
            "MattsSoftware-MenuBar", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 600
        do {
            let (file, _) = try await URLSession.shared.download(
                for: req)
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "mattssoftware-\(id)-\(getpid())-\(UUID().uuidString).dmg"
                )
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: file, to: dest)
            return dest
        } catch {
            throw InstallError.download(error.localizedDescription)
        }
    }

    /// Attach the dmg and return its mountpoint. Caller is
    /// responsible for `hdiutil detach`. No `-quiet`: we parse
    /// hdiutil's device→mountpoint table from stdout and `-quiet`
    /// suppresses all of it.
    private static func mountDMG(_ dmg: URL) throws -> String {
        let attach = run(
            "/usr/bin/hdiutil",
            [
                "attach", "-nobrowse", "-noverify",
                dmg.path, "-mountrandom", "/tmp",
            ])
        guard attach.ok else {
            throw InstallError.mount(attach.err)
        }
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
        return mountPoint
    }

    private static func appInDMG(_ mountPoint: String) -> String? {
        guard
            let entries = try? FileManager.default
                .contentsOfDirectory(atPath: mountPoint),
            let appName = entries.first(where: {
                $0.hasSuffix(".app")
            })
        else { return nil }
        return appName
    }

    /// Download → attach → ditto into /Applications → detach.
    /// `phase` is called with a short human status for the menu UI.
    static func installApp(
        _ app: CatalogApp,
        downloadURL: String,
        phase: @escaping (String) -> Void
    ) async throws -> String {
        phase("Downloading…")
        let tmp = try await downloadDMG(downloadURL, id: app.id)
        defer { try? FileManager.default.removeItem(at: tmp) }

        phase("Mounting…")
        let mountPoint = try mountDMG(tmp)
        defer {
            run(
                "/usr/bin/hdiutil",
                ["detach", "-quiet", "-force", mountPoint])
        }

        phase("Copying…")
        guard let appName = appInDMG(mountPoint) else {
            throw InstallError.noApp
        }
        let fm = FileManager.default
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

    /// Self-update for the launcher itself. We can't ditto over our
    /// own running bundle, so: download + mount here, then hand the
    /// swap to a detached shell helper that waits for THIS process
    /// to exit, replaces /Applications/MattsSoftware.app, cleans up
    /// the dmg, and relaunches us. Caller terminates the app right
    /// after this returns.
    static func selfUpdate(
        downloadURL: String,
        phase: @escaping (String) -> Void
    ) async throws {
        phase("Downloading…")
        let dmg = try await downloadDMG(downloadURL, id: "mattssoftware")
        phase("Mounting…")
        let mountPoint = try mountDMG(dmg)
        guard let appName = appInDMG(mountPoint) else {
            run(
                "/usr/bin/hdiutil",
                ["detach", "-quiet", "-force", mountPoint])
            try? FileManager.default.removeItem(at: dmg)
            throw InstallError.noApp
        }
        let src = "\(mountPoint)/\(appName)"
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/bash
        P="$1"; SRC="$2"; MP="$3"; DMG="$4"
        DST="/Applications/MattsSoftware.app"
        while /bin/kill -0 "$P" 2>/dev/null; do /bin/sleep 0.3; done
        /bin/sleep 0.5
        /usr/bin/ditto "$SRC" "$DST"
        /usr/bin/xattr -dr com.apple.quarantine "$DST" 2>/dev/null
        /usr/bin/hdiutil detach -quiet -force "$MP" 2>/dev/null
        /bin/rm -f "$DMG"
        /usr/bin/open "$DST"
        /bin/rm -f "$0"
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ms-selfupdate-\(pid).sh")
        try script.write(
            to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        phase("Relaunching…")
        // Detached: not waited on, so it outlives our termination.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [
            scriptURL.path, String(pid), src, mountPoint, dmg.path,
        ]
        try p.run()
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

    /// Is a process for this app currently running?
    static func isRunning(_ bundleName: String) -> Bool {
        if run("/usr/bin/pgrep", ["-x", bundleName]).ok {
            return true
        }
        // Tauri/other bundles whose exec name ≠ bundle name.
        return run(
            "/usr/bin/pgrep",
            ["-f", "/Applications/\(bundleName).app/Contents/MacOS/"]
        ).ok
    }

    /// Force the app shut: ask it nicely, then hard-kill by exact
    /// process name and by bundle exec path (covers Tauri apps).
    static func forceQuit(_ bundleName: String) {
        _ = run(
            "/usr/bin/osascript",
            ["-e", "tell application \"\(bundleName)\" to quit"])
        _ = run("/usr/bin/pkill", ["-x", bundleName])
        _ = run(
            "/usr/bin/pkill",
            ["-f", "/Applications/\(bundleName).app/Contents/MacOS/"])
    }

    /// Move the installed bundle to the Trash (recoverable — never
    /// an unrecoverable rm). Throws if it isn't there / can't move.
    static func trashApp(_ bundleName: String) throws {
        let url = URL(fileURLWithPath: appBundlePath(bundleName))
        try FileManager.default.trashItem(
            at: url, resultingItemURL: nil)
    }

    // MARK: Bundled icons

    private static var iconCache: [String: NSImage] = [:]

    /// Locate a bundled PNG WITHOUT SwiftPM's `Bundle.module`.
    /// That accessor `fatalError`s when it can't find the resource
    /// bundle, and in a hand-assembled .app it only ever resolved
    /// via a hardcoded dev `.build` path — so any other machine
    /// crashed on the first popover render. package.sh copies the
    /// PNGs straight into the app's Contents/Resources, so look
    /// there via Bundle.main first; the dev fallbacks cover
    /// `swift run`. A miss returns nil — a blank icon, never a crash.
    private static func iconURL(_ asset: String) -> URL? {
        if let u = Bundle.main.url(
            forResource: asset, withExtension: "png")
        {
            return u
        }
        let fm = FileManager.default
        let exeDir = Bundle.main.executableURL?
            .deletingLastPathComponent()
        let sourceDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
        let candidates = [
            exeDir?.appendingPathComponent("\(asset).png"),
            sourceDir.appendingPathComponent("\(asset).png"),
        ]
        return candidates
            .compactMap { $0 }
            .first { fm.fileExists(atPath: $0.path) }
    }

    /// Real squircle icon for a catalog row. Cached so scrolling
    /// the list doesn't re-decode.
    static func appIcon(_ asset: String) -> NSImage? {
        if let hit = iconCache[asset] { return hit }
        guard let url = iconURL(asset),
              let img = NSImage(contentsOf: url)
        else { return nil }
        iconCache[asset] = img
        return img
    }

    /// MattsSoftware brand mark for the popover header — the `>|M`
    /// wordmark glyph (white on transparent).
    static let brandIcon: NSImage? = appIcon("brandmark")
}

/// Disk-backed cache of each repo's latest-release lookup, keyed by
/// `owner/repo`. Persisted to ~/Library/Caches so it survives
/// relaunches — that, plus the stored ETag for conditional
/// requests, is what keeps the launcher under GitHub's 60-req/hr
/// unauthenticated limit (the cause of the Peephole 403s). An actor
/// so the concurrent `refresh()` task-group can't corrupt the file.
actor ReleaseCache {
    static let shared = ReleaseCache()

    struct Entry: Codable {
        var tag: String
        var dmg: String?
        var etag: String?
        var fetchedAt: Date
    }

    private var map: [String: Entry] = [:]
    private var loaded = false

    private var fileURL: URL {
        let base =
            FileManager.default.urls(
                for: .cachesDirectory, in: .userDomainMask
            ).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(
            "com.mattssoftware.launcher", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("releases.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let d = try? Data(contentsOf: fileURL),
           let m = try? JSONDecoder().decode(
               [String: Entry].self, from: d) {
            map = m
        }
    }

    func get(_ repo: String) -> Entry? {
        loadIfNeeded()
        return map[repo]
    }

    func set(_ repo: String, _ entry: Entry) {
        loadIfNeeded()
        map[repo] = entry
        if let d = try? JSONEncoder().encode(map) {
            try? d.write(to: fileURL, options: .atomic)
        }
    }
}

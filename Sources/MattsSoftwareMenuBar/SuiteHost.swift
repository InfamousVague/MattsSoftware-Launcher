import AppKit
import SwiftUI
import SuiteKit

/// Loads feature panes at runtime out of *installed* sibling apps
/// (or a dev `.build` fallback) and exposes them — alongside the
/// built-in Apps catalog — to the switcher. The launcher itself
/// carries none of those apps' code; this just `dlopen`s their
/// embedded `lib<App>Pane.dylib`, pulls the `SuitePane` out, keeps
/// it alive, and coordinates with the standalone agent so you never
/// get a duplicate menu-bar icon.
@MainActor
@Observable
final class SuiteHost {

    /// One switcher slot: the built-in Apps pane, or a loaded
    /// feature pane (or a stub when the installed app is too old).
    struct Entry: Identifiable {
        let id: String          // paneID, or "apps"
        let title: String
        let tint: Color
        let image: NSImage      // template glyph for the segment
        let view: NSView?       // nil ⇒ built-in Apps pane / needsUpdate
        let pane: SuitePane?    // nil ⇒ built-in Apps pane / needsUpdate
        var needsUpdate = false // ABI mismatch with this launcher
    }

    /// An app the launcher knows how to absorb. Extended as panes
    /// roll out; pairs a catalog id with its embedded pane dylib.
    struct SuiteApp: Sendable, Identifiable {
        let id: String
        let displayName: String
        let bundleID: String    // standalone app's CFBundleIdentifier
        let appBundle: String   // "Espresso.app"
        let paneLib: String     // "libEspressoPane.dylib"
        let devRepo: String     // sibling repo for the dev fallback
    }

    nonisolated static let registry: [SuiteApp] = [
        .init(id: "espresso", displayName: "Espresso",
              bundleID: "com.mattssoftware.espresso",
              appBundle: "Espresso.app",
              paneLib: "libEspressoPane.dylib",
              devRepo: "espresso-swift")
    ]

    private(set) var entries: [Entry] = []
    var selected: String = "apps"

    /// A pane that's been dlopen'd at least once. Reused on rebuild
    /// so toggling merge on/off never re-`dlopen`s or double-starts.
    private struct Loaded {
        let handle: UnsafeMutableRawPointer
        let pane: SuitePane
        let view: NSView?       // nil until first activated
        let abiOK: Bool
        var started: Bool
    }
    private var cache: [String: Loaded] = [:]

    // MARK: Discovery

    nonisolated private func resolveDylib(_ a: SuiteApp) -> URL? {
        let fm = FileManager.default
        for d in ["/Applications", NSHomeDirectory() + "/Applications"] {
            let p = "\(d)/\(a.appBundle)/Contents/Frameworks/\(a.paneLib)"
            if fm.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        }
        let dev = "\(NSHomeDirectory())/Development/Apps/"
            + "\(a.devRepo)/.build/debug/\(a.paneLib)"
        if fm.fileExists(atPath: dev) { return URL(fileURLWithPath: dev) }
        return nil
    }

    /// Is this app present at all (installed or dev-built)? Drives
    /// the settings list — you can't merge what isn't there.
    nonisolated func appAvailable(_ a: SuiteApp) -> Bool {
        resolveDylib(a) != nil
    }

    // MARK: Loading

    /// dlopen + cast + ABI check for one app, caching the result.
    /// Returns the cached entry, loading it the first time.
    private func ensureLoaded(_ app: SuiteApp,
                              activate: Bool) -> Loaded? {
        if var c = cache[app.id] {
            if activate && c.abiOK && !c.started {
                c.pane.paneStart()
                c = Loaded(handle: c.handle, pane: c.pane,
                           view: c.view ?? c.pane.paneMakeView(),
                           abiOK: c.abiOK, started: true)
                cache[app.id] = c
            }
            return c
        }
        guard let url = resolveDylib(app) else { return nil }
        guard let h = dlopen(url.path, RTLD_NOW) else {
            NSLog("SuiteHost: dlopen \(app.id) failed: "
                + "\(String(cString: dlerror()))")
            return nil
        }
        guard let sym = dlsym(h, kSuitePaneCreateSymbol) else {
            NSLog("SuiteHost: \(kSuitePaneCreateSymbol) missing in "
                + "\(app.id)")
            return nil
        }
        let create = unsafeBitCast(sym, to: SuitePaneCreateFn.self)
        guard let pane = create().takeRetainedValue() as? SuitePane
        else {
            NSLog("SuiteHost: \(app.id) is not a SuitePane — "
                + "SuiteKit identity not shared")
            return nil
        }
        let abiOK = pane.suiteABIVersion == SuiteKitABI.current
        if abiOK && activate { pane.paneStart() }
        let loaded = Loaded(
            handle: h, pane: pane,
            view: (abiOK && activate) ? pane.paneMakeView() : nil,
            abiOK: abiOK,
            started: abiOK && activate)
        cache[app.id] = loaded
        return loaded
    }

    private var appsEntry: Entry {
        Entry(id: "apps", title: "APPS", tint: .accentColor,
              image: NSImage(systemSymbolName: "square.grid.2x2",
                             accessibilityDescription: "Apps")
                     ?? NSImage(),
              view: nil, pane: nil)
    }

    /// (Re)build the switcher list from the cache + the merge set.
    /// `mergedIDs` is the user's setting — only those apps are
    /// absorbed; the rest keep running standalone.
    func loadPanes(mergedIDs: Set<String>, activate: Bool = true) {
        var list: [Entry] = [appsEntry]
        for app in Self.registry where mergedIDs.contains(app.id) {
            guard let l = ensureLoaded(app, activate: activate)
            else { continue }
            list.append(Entry(
                id: l.pane.paneID,
                title: l.pane.paneTitle,
                tint: Color(suiteHex: l.pane.paneTintHex)
                      ?? .accentColor,
                image: l.pane.paneMenuBarImage(),
                view: l.abiOK ? l.view : nil,
                pane: l.abiOK ? l.pane : nil,
                needsUpdate: !l.abiOK))
        }
        entries = list
        if !list.contains(where: { $0.id == selected }) {
            selected = "apps"
        }
    }

    /// Rebuild from the persisted setting (used after a toggle).
    func reload() { loadPanes(mergedIDs: SuiteSettings.mergedIDs()) }

    // MARK: Merge toggle + standalone coordination

    /// Flip one app between merged (a launcher pane) and standalone
    /// (its own menu-bar agent), persist it, and make the world
    /// match: merging quits the running standalone agent; going
    /// standalone relaunches it.
    func setMerged(_ app: SuiteApp, _ merged: Bool) {
        SuiteSettings.setStandalone(app.id, !merged)
        if merged {
            terminateStandalone(app)          // no duplicate icon
            _ = ensureLoaded(app, activate: true)
        } else {
            if let c = cache[app.id], c.started {
                c.pane.paneStop()
                cache[app.id] = Loaded(
                    handle: c.handle, pane: c.pane, view: c.view,
                    abiOK: c.abiOK, started: false)
            }
            if selected == app.id { selected = "apps" }
            relaunchStandalone(app)
        }
        reload()
    }

    /// Quit any running standalone instance so merging it doesn't
    /// leave a second menu-bar icon. (Login-item relaunch is handled
    /// by the app itself via `SuiteGuard.exitIfDeferring`.)
    private func terminateStandalone(_ app: SuiteApp) {
        for r in NSRunningApplication.runningApplications(
            withBundleIdentifier: app.bundleID) {
            r.terminate()
        }
    }

    /// Relaunch the installed standalone app when the user unmerges
    /// it (best effort — only if it's actually installed, not a
    /// bare dev build).
    private func relaunchStandalone(_ app: SuiteApp) {
        let fm = FileManager.default
        for d in ["/Applications", NSHomeDirectory() + "/Applications"] {
            let p = "\(d)/\(app.appBundle)"
            if fm.fileExists(atPath: p) {
                NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: p),
                    configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
    }
}

extension Color {
    /// "#RRGGBB" → Color (the app hue carried over the SuiteKit
    /// boundary, since Color isn't @objc-bridgeable).
    init?(suiteHex: String) {
        var s = suiteHex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            return nil
        }
        self.init(.sRGB,
                  red:   Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >>  8) & 0xFF) / 255,
                  blue:  Double( v        & 0xFF) / 255)
    }
}

/// Drops a pane's AppKit view (an `NSHostingView` over its own
/// SwiftUI root) into the launcher's SwiftUI tree.
struct PaneContainer: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

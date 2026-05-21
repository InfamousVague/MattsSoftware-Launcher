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

    /// One switcher slot: the built-in Apps pane, a loaded feature
    /// pane (merged, lives inside the launcher), or an "external"
    /// installed app the user has pinned to Standalone — that one
    /// has no in-process view; clicking it opens the .app.
    struct Entry: Identifiable {
        let id: String          // paneID, or "apps"
        let title: String
        let tint: Color
        let image: NSImage      // segment glyph
        let view: NSView?       // nil ⇒ built-in / external / needsUpdate
        let pane: SuitePane?    // nil ⇒ built-in / external / needsUpdate
        /// Non-nil ⇒ external entry: clicking it opens the .app at
        /// this URL (standalone-pinned apps route through this).
        var openURL: URL? = nil
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
        // Pane has no standalone download — it ships embedded
        // inside another app's Resources, so the host app is the
        // only thing the user installs. Currently unused (no app
        // in the registry needs this), but the resolveDylib path
        // still honours it if a future entry sets it.
        var hostedIn: String? = nil
    }

    nonisolated static let registry: [SuiteApp] = [
        .init(id: "sentry", displayName: "Sentry",
              bundleID: "com.mattssoftware.sentry",
              appBundle: "Sentry.app",
              paneLib: "libSentryPane.dylib",
              devRepo: "sentry-swift"),
        .init(id: "peephole", displayName: "Peephole",
              bundleID: "com.mattssoftware.peephole",
              appBundle: "Peephole.app",
              paneLib: "libPeepholePane.dylib",
              devRepo: "peephole-swift"),
        .init(id: "port", displayName: "Port",
              bundleID: "com.mattssoftware.port",
              appBundle: "Port.app",
              paneLib: "libPortPane.dylib",
              devRepo: "port-swift"),
        .init(id: "stats", displayName: "Stats",
              bundleID: "com.mattssoftware.stats",
              appBundle: "Stats.app",
              paneLib: "libStatsPane.dylib",
              devRepo: "stats-swift"),
        .init(id: "quarantine", displayName: "Quarantine",
              bundleID: "com.mattssoftware.quarantine",
              appBundle: "Quarantine.app",
              paneLib: "libQuarantinePane.dylib",
              devRepo: "quarantine-swift"),
        .init(id: "espresso", displayName: "Espresso",
              bundleID: "com.mattssoftware.espresso",
              appBundle: "Espresso.app",
              paneLib: "libEspressoPane.dylib",
              devRepo: "espresso-swift"),
        .init(id: "stickykeys", displayName: "StickyKeys",
              bundleID: "com.mattssoftware.stickykeys",
              appBundle: "StickyKeys.app",
              paneLib: "libStickyKeysPane.dylib",
              devRepo: "stickykeys-swift"),
        .init(id: "alfred", displayName: "Alfred",
              bundleID: "com.mattssoftware.alfred",
              appBundle: "Alfred.app",
              paneLib: "libAlfredPane.dylib",
              devRepo: "Alfred")
    ]

    /// Tray-style SF Symbol per app id — used to render the
    /// carousel segment for external (standalone-pinned) entries
    /// without dlopening the pane. Keeps the carousel consistent:
    /// every entry is a template glyph in the same visual family
    /// as the menu-bar status item, not a mini full-colour squircle.
    /// (Alfred has no SF analogue; it falls back to reading the
    /// installed bundle's `Contents/Resources/MenuBarIcon.png`.)
    nonisolated static let traySymbols: [String: String] = [
        "sentry":     "shield.lefthalf.filled",
        "peephole":   "eye.trianglebadge.exclamationmark",
        "port":       "sailboat.fill",
        "stats":      "waveform.path.ecg",
        "quarantine": "square.and.arrow.down",
        "espresso":   "cup.and.saucer",
        "stickykeys": "keyboard",
    ]

    private(set) var entries: [Entry] = []
    var selected: String = "apps"

    /// Diagnostic view of every pane we've successfully dlopen'd +
    /// cast through SuiteKit, regardless of whether it's been
    /// started / appears in the carousel. Drives `SuiteSelfTest`,
    /// which proves the runtime-pane plumbing works without having
    /// to paneStart (that needs a real run loop, not a shell-launched
    /// headless invocation).
    struct DiscoveredPane {
        let id: String
        let abiVersion: Int
        let abiOK: Bool
    }
    var discoveredPanes: [DiscoveredPane] {
        cache.map { id, l in
            DiscoveredPane(
                id: id,
                abiVersion: Int(l.pane.suiteABIVersion),
                abiOK: l.abiOK)
        }.sorted { $0.id < $1.id }
    }

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
        let appDirs = ["/Applications",
                       NSHomeDirectory() + "/Applications"]
        // 1) Installed as its own app.
        for d in appDirs {
            let p = "\(d)/\(a.appBundle)/Contents/Frameworks/\(a.paneLib)"
            if fm.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        }
        // 2) Embedded inside another app's Resources — the host app
        //    is the only thing the user installs (Developer-ID signed
        //    by the same team, so Library Validation still lets us
        //    dlopen it). Unused right now; kept for future apps.
        if let host = a.hostedIn {
            for d in appDirs {
                let p = "\(d)/\(host)/Contents/Resources/"
                    + "\(a.appBundle)/Contents/Frameworks/\(a.paneLib)"
                if fm.fileExists(atPath: p) {
                    return URL(fileURLWithPath: p)
                }
            }
        }
        // 3) Dev fallback.
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
        // Home tab uses the MattsSoftware launcher squircle so the
        // carousel reads as a uniform strip of full-colour app icons.
        let img = Services.appIcon("launcher")
            ?? NSImage(systemSymbolName: "square.grid.2x2",
                       accessibilityDescription: "Apps")
            ?? NSImage()
        return Entry(id: "apps", title: "APPS", tint: .accentColor,
                     image: img, view: nil, pane: nil)
    }

    /// Path to the installed .app bundle, if present. Used to gate
    /// switcher inclusion (carousel only shows installed apps) and
    /// to know what to NSWorkspace-open for external entries.
    nonisolated func installedAppURL(_ a: SuiteApp) -> URL? {
        let fm = FileManager.default
        for d in ["/Applications", NSHomeDirectory() + "/Applications"] {
            let direct = "\(d)/\(a.appBundle)"
            if fm.fileExists(atPath: direct) {
                return URL(fileURLWithPath: direct)
            }
            // Embedded inside a host app's Resources — still
            // treat that as "installed" (unused right now; kept
            // for future entries that set `hostedIn`).
            if let host = a.hostedIn {
                let nested = "\(d)/\(host)/Contents/Resources/\(a.appBundle)"
                if fm.fileExists(atPath: nested) {
                    return URL(fileURLWithPath: nested)
                }
            }
        }
        return nil
    }

    /// (Re)build the switcher list from what's actually installed.
    /// Each installed registry app appears in the carousel:
    ///  • merged + pane loadable  →  full pane entry (click switches
    ///    the host's content tab to it, in-process).
    ///  • standalone (or merged but pane unavailable) → "external"
    ///    entry (click opens the standalone .app, the launcher's
    ///    `didLaunchApplication` observer takes over if it later
    ///    needs to surface a tab).
    /// Apps not in /Applications never show up — FSEvents on
    /// /Applications drives reloads so this is live.
    ///
    /// `activate` is **false by default**: at launcher boot we want
    /// every pane discoverable in the carousel, but none of them
    /// actually *running* (no event taps, no timers, no observers)
    /// until the user explicitly opens one. `openMerged(_:)` flips
    /// activation on for a single pane the first time it's opened.
    func loadPanes(mergedIDs: Set<String>, activate: Bool = false) {
        var list: [Entry] = [appsEntry]
        for app in Self.registry {
            // Has to be installed (or dev-built) AND set to merged.
            // Standalone-pinned apps live in their own menu-bar icon
            // and never show up in the launcher's carousel — open
            // them from there or from /Applications.
            guard installedAppURL(app) != nil,
                  mergedIDs.contains(app.id),
                  let l = ensureLoaded(app, activate: activate)
            else { continue }
            // The carousel reads as a tab strip of *opened* panes —
            // nothing shows up here until the user explicitly opens
            // it (catalog Open, launching the .app, notification
            // tap; all of those route through `openMerged(_:)`). The
            // one exception: a needs-update pane surfaces immediately
            // so the user actually finds out it's stale.
            guard l.started || !l.abiOK else { continue }
            // Carousel image is the playful-3D catalog squircle
            // (bundled in the launcher), not the pane's tray glyph —
            // keeps the strip a uniform row of full-colour icons.
            let img = Services.appIcon(app.id)
                ?? l.pane.paneMenuBarImage()
            list.append(Entry(
                id: l.pane.paneID,
                title: l.pane.paneTitle,
                tint: Color(suiteHex: l.pane.paneTintHex)
                      ?? .accentColor,
                image: img,
                view: l.abiOK ? l.view : nil,
                pane: l.abiOK ? l.pane : nil,
                openURL: nil,
                needsUpdate: !l.abiOK))
        }
        entries = list
        if !list.contains(where: { $0.id == selected }) {
            selected = "apps"
        }
    }

    /// Launches the external app behind the given entry id (a
    /// standalone-pinned suite app). No-op if the entry isn't
    /// external or the app vanished between the click and now.
    func openExternal(_ id: String) {
        guard let entry = entries.first(where: { $0.id == id }),
              let url = entry.openURL else { return }
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration())
    }

    /// Switch to a switcher entry, lazily starting its pane the first
    /// time it's opened. This is the **only** path that should call
    /// `paneStart()` — boot, FSEvents reloads, and merge toggles all
    /// stay inert so an installed pane never runs until the user
    /// actually opens it (from the carousel, the catalog "Open"
    /// button, or by launching the .app from /Applications).
    ///
    /// Opening a pane also makes it appear in the carousel — that's
    /// how the strip stays a clean "tabs you've opened" list rather
    /// than a wall of every installed app.
    func openMerged(_ id: String) {
        // Built-in tabs: just select them, nothing to start.
        if id == "apps" || id == "settings" {
            selected = id
            return
        }
        // Merged registry app: lazily start, rebuild entries so the
        // freshly-built view is wired in (cache is reused; no double
        // dlopen / start), then select it.
        if let app = Self.registry.first(where: { $0.id == id }),
           SuiteSettings.mergedIDs().contains(id) {
            _ = ensureLoaded(app, activate: true)
            loadPanes(mergedIDs: SuiteSettings.mergedIDs())
            selected = id
            return
        }
        // Standalone-pinned or unknown id: no carousel entry exists
        // for it — silently ignore rather than leave the launcher in
        // a state where `selected` points at nothing.
    }

    /// Rebuild from the persisted setting (used after a toggle).
    /// Inert by default — no pane is paneStart-ed here; the user has
    /// to actually open one via `openMerged(_:)`.
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
            // Lazy: dlopen so the carousel knows about it (and can
            // flag ABI mismatch), but don't paneStart — the user has
            // to actually open it for the runtime to fire up.
            _ = ensureLoaded(app, activate: false)
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
///
/// Switching segments keeps ONE `PaneContainer` (same SwiftUI
/// identity), so SwiftUI calls `updateNSView`, not `makeNSView`.
/// The old no-op `updateNSView` is why the body never changed until
/// you bounced through the APPS tab (a different view type forced a
/// rebuild). This hosts the pane inside a wrapper and swaps the
/// child whenever the selected pane's view changes; the child is
/// pinned on all edges so the wrapper inherits the pane's own
/// fixed size (popover sizing unchanged).
/// A plain wrapper that reports its hosted pane's size, so the
/// NSPopover keeps sizing to the pane's own fixed frame.
final class PaneWrapper: NSView {
    override var intrinsicContentSize: NSSize {
        subviews.first?.fittingSize ?? super.intrinsicContentSize
    }
}

struct PaneContainer: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView {
        let wrapper = PaneWrapper()
        install(view, in: wrapper)
        return wrapper
    }

    func updateNSView(_ wrapper: NSView, context: Context) {
        guard view.superview !== wrapper else { return }
        wrapper.subviews.forEach { $0.removeFromSuperview() }
        install(view, in: wrapper)
    }

    private func install(_ v: NSView, in wrapper: NSView) {
        v.removeFromSuperview()
        v.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(
                equalTo: wrapper.leadingAnchor),
            v.trailingAnchor.constraint(
                equalTo: wrapper.trailingAnchor),
            v.topAnchor.constraint(equalTo: wrapper.topAnchor),
            v.bottomAnchor.constraint(
                equalTo: wrapper.bottomAnchor),
        ])
        wrapper.invalidateIntrinsicContentSize()
    }
}

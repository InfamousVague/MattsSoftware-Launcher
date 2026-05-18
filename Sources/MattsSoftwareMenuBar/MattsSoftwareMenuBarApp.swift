import AppKit
import SwiftUI

/// Process entry point. Normally just boots the SwiftUI app, but
/// if `MS_INSTALL_TEST=<app-id>` is set it runs the real install
/// pipeline for that app headlessly and exits — same signed bundle
/// identity as a normal launch, so it faithfully reproduces (and
/// proves out) download → mount → ditto → detach, including any
/// /Applications permission / TCC behaviour. Inert without the var.
@main
enum Bootstrap {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        if let id = env["MS_INSTALL_TEST"], !id.isEmpty {
            InstallSelfTest.run(appId: id)  // calls exit(), never returns
        }
        if env["MS_ICON_TEST"] != nil {
            IconSelfTest.run()              // calls exit(), never returns
        }
        MattsSoftwareMenuBarApp.main()
    }
}

/// Headless check that every catalog icon (+ the brand mark)
/// resolves from the app bundle with NO dependency on SwiftPM's
/// `Bundle.module` / the dev `.build` dir — i.e. that it won't
/// crash on another machine. Exits 0 only if all resolve. Driven
/// by `MS_ICON_TEST`.
enum IconSelfTest {
    static func run() -> Never {
        var missing: [String] = []
        if Services.brandIcon == nil { missing.append("launcher") }
        for app in CATALOG where Services.appIcon(app.iconAsset) == nil {
            missing.append(app.iconAsset)
        }
        if missing.isEmpty {
            print("✓ all \(CATALOG.count + 1) icons resolved "
                + "from the app bundle (no Bundle.module)")
            exit(0)
        }
        print("✗ unresolved icons: \(missing.joined(separator: ", "))")
        exit(1)
    }
}

/// Headless end-to-end check of `Services.installApp` for one
/// catalog id. Prints each phase + the final outcome, then exits
/// (0 = installed, 1 = any failure). Driven by `MS_INSTALL_TEST`.
enum InstallSelfTest {
    static func run(appId: String) -> Never {
        guard let app = CATALOG.first(where: { $0.id == appId }) else {
            FileHandle.standardError.write(
                Data("self-test: unknown app id '\(appId)'\n".utf8))
            exit(2)
        }
        let sem = DispatchSemaphore(value: 0)
        var code: Int32 = 1
        Task {
            print("• resolving status for \(app.name)…")
            let st = await Services.resolveStatus(app)
            print("  installed=\(st.installed) "
                + "installedVersion=\(st.installedVersion ?? "—") "
                + "latest=\(st.latestVersion ?? "—")")
            guard let url = st.downloadURL else {
                print("✗ no download URL "
                    + "(error: \(st.error ?? "none"))")
                sem.signal()
                return
            }
            print("• download URL: \(url)")
            do {
                let dst = try await Services.installApp(
                    app, downloadURL: url
                ) { print("  phase: \($0)") }
                print("✓ installed at \(dst)")
                code = 0
            } catch {
                print("✗ install failed: "
                    + "\(error.localizedDescription)")
            }
            sem.signal()
        }
        sem.wait()
        exit(code)
    }
}

/// App shell. Built the exact way every other MattsSoftware
/// menu-bar app is (Sentry, Port, Peephole, …): an empty `Settings`
/// scene plus an `NSApplicationDelegateAdaptor` that owns an
/// `NSStatusItem` and a transient `NSPopover`. The activation
/// policy is flipped to `.accessory` so there's no Dock icon / app
/// menu — MattsSoftware lives purely in the status bar.
struct MattsSoftwareMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The real UI is the NSStatusItem/NSPopover the delegate
        // manages; this scene stays empty and is never shown.
        Settings { EmptyView() }
    }

    /// Menu-bar glyph — `square.grid.2x2` echoes the launcher's
    /// "grid of apps" mark. Set as a template so macOS tints it for
    /// the active menu-bar appearance (dark on light bars, light on
    /// dark), identical to the sibling apps' status glyphs.
    static let menuBarIcon: NSImage = {
        let image = NSImage(
            systemSymbolName: "square.grid.2x2",
            accessibilityDescription: "MattsSoftware"
        ) ?? NSImage()
        let config = NSImage.SymbolConfiguration(
            pointSize: 15, weight: .regular)
        let configured = image.withSymbolConfiguration(config) ?? image
        configured.isTemplate = true
        return configured
    }()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate,
    NSPopoverDelegate
{
    let state = AppState()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    /// Global click monitor used to dismiss the popover on any click
    /// outside it — `.transient` alone is unreliable for `.accessory`
    /// apps once we `NSApp.activate`, so this is the backstop.
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = MattsSoftwareMenuBarApp.menuBarIcon
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.toolTip = "MattsSoftware — every app I've built"
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView().environmentObject(state)
        )

        // Warm the catalog so the first popover open already shows
        // installed/update state instead of a flash of spinners.
        Task { await state.refresh() }
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY)
        if let win = popover.contentViewController?.view.window {
            clampOnScreen(win, anchoredTo: button)
            win.makeKey()
        }
        NSApp.activate(ignoringOtherApps: true)

        // Close on any mouse-down outside this app (menu bar, desk‑
        // top, another window). The status-item click is handled by
        // `togglePopover`; clicks inside the popover never reach a
        // global monitor.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    /// Keep the popover fully on the screen that holds the status
    /// item. NSPopover centers on the icon and clips when the icon
    /// is near a screen edge (notably far right / next to the
    /// notch); shift the window back inside the visible frame.
    private func clampOnScreen(_ win: NSWindow, anchoredTo anchor: NSView) {
        guard let screen = anchor.window?.screen ?? NSScreen.main
        else { return }
        let vis = screen.visibleFrame
        let pad: CGFloat = 8
        var f = win.frame
        if f.maxX > vis.maxX - pad {
            f.origin.x = vis.maxX - pad - f.width
        }
        if f.minX < vis.minX + pad {
            f.origin.x = vis.minX + pad
        }
        if f.minY < vis.minY + pad {
            f.origin.y = vis.minY + pad
        }
        if f != win.frame {
            win.setFrame(f, display: true)
        }
    }

    // NSPopoverDelegate — fires however the popover closed
    // (transient, Esc, performClose); always tear the monitor down
    // so it can't leak or fire after dismissal.
    func popoverDidClose(_ notification: Notification) {
        if let m = clickMonitor {
            NSEvent.removeMonitor(m)
            clickMonitor = nil
        }
    }
}

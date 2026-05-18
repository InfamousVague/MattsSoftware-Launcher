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
        if let id = ProcessInfo.processInfo
            .environment["MS_INSTALL_TEST"], !id.isEmpty
        {
            InstallSelfTest.run(appId: id)  // calls exit(), never returns
        }
        MattsSoftwareMenuBarApp.main()
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
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

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
        popover.contentViewController?.view.window?
            .makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }
}

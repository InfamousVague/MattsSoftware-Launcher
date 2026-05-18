import AppKit
import SwiftUI

/// Menu-bar-only companion. `@NSApplicationDelegateAdaptor` flips
/// the activation policy to `.accessory` so there's no Dock icon /
/// app menu — it lives purely in the status bar, the way a launcher
/// helper should.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct MattsSoftwareMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(state)
        } label: {
            // SF Symbol — the menu-bar glyph. `square.grid.2x2`
            // echoes the launcher's "grid of apps" mark.
            Image(systemName: "square.grid.2x2")
        }
        .menuBarExtraStyle(.window)
    }
}

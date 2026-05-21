import AppKit
import ApplicationServices

/// Some merged panes need a TCC permission that macOS binds to the
/// *host* process. StickyKeys is the case in point: merged, its
/// `CGEventTap` runs inside MattsSoftware's process, so MattsSoftware
/// — not StickyKeys.app — must be Accessibility-trusted.
///
/// On first launch with such a pane merged and the launcher not yet
/// trusted, register + prompt, open the Settings pane, and offer to
/// relaunch (an event tap denied at create-time only picks up a new
/// grant after the process restarts).
@MainActor
enum AccessibilityGate {
    /// Pane IDs whose feature needs Accessibility while merged.
    static let neededBy: Set<String> = ["stickykeys"]

    static func ensureIfNeeded(mergedIDs: Set<String>) {
        guard !neededBy.isDisjoint(with: mergedIDs) else { return }
        if AXIsProcessTrusted() { return }

        // Registers MattsSoftware in the Accessibility list and shows
        // the system prompt.
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)

        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        let names = neededBy.intersection(mergedIDs)
            .map { $0.capitalized }.sorted()
            .joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = "MattsSoftware needs Accessibility"
        alert.informativeText =
            "\(names) runs inside MattsSoftware and needs the Accessibility "
            + "permission to control the keyboard.\n\n"
            + "Enable “MattsSoftware” under System Settings → Privacy & "
            + "Security → Accessibility, then relaunch — a fresh start is "
            + "required for the permission to take effect."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "I’ve enabled it — Relaunch")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            relaunch()
        }
    }

    private static func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }
}

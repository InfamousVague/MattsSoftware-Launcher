import Foundation
import SuiteKit

/// Thin launcher-side facade over `SuiteGuard`'s shared merge.json,
/// so the launcher and every standalone app agree on which apps are
/// merged. Merge-by-default: installing an app makes it appear in
/// the switcher automatically; opting one out is the explicit act.
enum SuiteSettings {
    static func standaloneIDs() -> Set<String> {
        SuiteGuard.standaloneIDs()
    }

    static func mergedIDs() -> Set<String> {
        Set(SuiteHost.registry.map(\.id))
            .subtracting(SuiteGuard.standaloneIDs())
    }

    static func isStandalone(_ id: String) -> Bool {
        !SuiteGuard.isMerged(id)
    }

    static func setStandalone(_ id: String, _ standalone: Bool) {
        SuiteGuard.setMerged(id, !standalone)
    }

    // MARK: - Dynamic Island

    /// UserDefaults key for the notch-pinned live-activity pill
    /// (the "Dynamic Island" feature). On by default — users who
    /// don't want it toggle it off in launcher settings.
    private static let dynamicIslandKey = "suite.dynamicIsland.enabled"

    static func dynamicIslandEnabled() -> Bool {
        let d = UserDefaults.standard
        // Treat absence as "true" so first launch shows the
        // feature; once the user toggles it the explicit value
        // sticks.
        if d.object(forKey: dynamicIslandKey) == nil { return true }
        return d.bool(forKey: dynamicIslandKey)
    }

    static func setDynamicIslandEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: dynamicIslandKey)
    }
}

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
}

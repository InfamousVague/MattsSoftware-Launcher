import Foundation

/// Distribution channel — how an app is fetched / opened.
enum Channel: String {
    case github
    case appstore
    case dmg
    case library
}

/// Display category — the menu groups the lineup under these.
/// `.launcher` is first so MattsSoftware's own self-update row
/// pins to the top of the list.
enum AppCategory: String, CaseIterable {
    case launcher = "Launcher"
    case developerTools = "Developer Tools"
    case privacySecurity = "Privacy & Security"
    case utilities = "Utilities"
    case learning = "Learning"
    case design = "Design"
}

/// One catalogued app — just what a menu row + its action needs.
struct CatalogApp: Identifiable {
    let id: String
    let name: String
    let tagline: String
    let category: AppCategory
    let channel: Channel
    /// `owner/repo` or bare `repo` (owner defaults to InfamousVague).
    let githubRepo: String?
    /// App Store / docs / direct-dmg URL depending on channel.
    let url: String?
    /// `.app` name in /Applications (no `.app`). nil = not a Mac
    /// app we install (Tap is watchOS; Base is a library).
    let bundleName: String?
    /// Bundled PNG basename (no extension) under Resources/, loaded
    /// via Bundle.main so each row shows the real squircle.
    let iconAsset: String
}

/// Every app I've shipped, sourced from the marketing site's
/// published copy (mattssoftware.com). Kept in display order.
/// MattsSoftware itself leads the list so it can OTA self-update
/// through the same pipeline as everything else.
let CATALOG: [CatalogApp] = [
    CatalogApp(
        id: "mattssoftware",
        name: "MattsSoftware",
        tagline: "The menu-bar launcher for every app I've built.",
        category: .launcher,
        channel: .github,
        githubRepo: "InfamousVague/MattsSoftware-Launcher",
        url: nil,
        bundleName: "MattsSoftware",
        iconAsset: "launcher"
    ),
    CatalogApp(
        id: "blip",
        name: "Blip",
        tagline: "Your computer has been talking behind your back.",
        category: .privacySecurity,
        channel: .github,
        githubRepo: "Blip",
        url: nil,
        bundleName: "Blip",
        iconAsset: "blip"
    ),
    CatalogApp(
        // Vyv was renamed to Espresso (the native-Swift rewrite):
        // repo + installed .app bundle both moved to "Espresso".
        id: "espresso",
        name: "Espresso",
        tagline: "Your computer wants to sleep. Espresso disagrees.",
        category: .utilities,
        channel: .github,
        githubRepo: "Espresso",
        url: nil,
        bundleName: "Espresso",
        iconAsset: "espresso"
    ),
    CatalogApp(
        // Seasick — Apple's iPhone Motion Cues, ported to the Mac.
        // Click-through particle overlay drifts opposite the
        // device's tilt; reads SMS / AirPods / iPhone-companion
        // motion. Standalone menu-bar agent, not a SuiteKit pane
        // (so it doesn't appear in SuiteHost.registry, only here
        // in the install catalog).
        id: "seasick",
        name: "Seasick",
        tagline: "Motion cues for your Mac.",
        category: .utilities,
        channel: .github,
        githubRepo: "Seasick",
        url: nil,
        bundleName: "Seasick",
        iconAsset: "seasick"
    ),
    CatalogApp(
        id: "diane",
        name: "Diane",
        tagline: "I'm holding in my hand a small tape recorder.",
        category: .utilities,
        channel: .github,
        githubRepo: "Diane",
        url: nil,
        bundleName: "Diane",
        iconAsset: "diane"
    ),
    CatalogApp(
        id: "stickykeys",
        name: "StickyKeys",
        tagline: "Lock the keyboard so a cleaning cloth can't fire shortcuts.",
        category: .utilities,
        channel: .github,
        githubRepo: "StickyKeys",
        url: nil,
        bundleName: "StickyKeys",
        iconAsset: "stickykeys"
    ),
    CatalogApp(
        // Crumb — file-provenance overlay. Quarantine xattr +
        // Spotlight WhereFroms (certain signals) + FSEvents +
        // frontmost-app capture (heuristic, clearly labelled in
        // the popover). Filed under utilities — Quarantine
        // covers downloads alone; Crumb is the everyday "where
        // did this file come from" lookup.
        id: "crumb",
        name: "Crumb",
        tagline: "Every file came from somewhere — Crumb shows where.",
        category: .utilities,
        channel: .github,
        githubRepo: "Crumb",
        url: nil,
        bundleName: "Crumb",
        iconAsset: "crumb"
    ),
    CatalogApp(
        id: "port",
        name: "Port",
        tagline: "Every open port on your Mac, one click away.",
        category: .developerTools,
        channel: .github,
        githubRepo: "Port",
        url: nil,
        bundleName: "Port",
        iconAsset: "port"
    ),
    CatalogApp(
        id: "peephole",
        name: "Peephole",
        tagline: "See who's watching.",
        category: .privacySecurity,
        channel: .github,
        githubRepo: "Peephole",
        url: nil,
        bundleName: "Peephole",
        iconAsset: "peephole"
    ),
    CatalogApp(
        id: "quarantine",
        name: "Quarantine",
        tagline: "Trust, but verify every download.",
        category: .privacySecurity,
        channel: .github,
        githubRepo: "Quarantine",
        url: nil,
        bundleName: "Quarantine",
        iconAsset: "quarantine"
    ),
    CatalogApp(
        id: "stats",
        name: "Stats",
        tagline: "Live CPU, memory, disk, network & sensors in your menu bar.",
        category: .utilities,
        channel: .github,
        githubRepo: "Stats",
        url: nil,
        bundleName: "Stats",
        iconAsset: "stats"
    ),
    CatalogApp(
        id: "sentry",
        name: "Sentry",
        tagline: "Know the moment something digs in.",
        category: .privacySecurity,
        channel: .github,
        githubRepo: "Sentry",
        url: nil,
        bundleName: "Sentry",
        iconAsset: "sentry"
    ),
    CatalogApp(
        id: "alfred",
        name: "Alfred",
        tagline: "Reclaim the disk space dev cruft is hoarding.",
        category: .developerTools,
        channel: .github,
        githubRepo: "Alfred",
        url: nil,
        bundleName: "Alfred",
        iconAsset: "alfred"
    ),
    CatalogApp(
        id: "uninstaller",
        name: "Uninstaller",
        tagline: "Apps + their crumbs, in one click.",
        category: .utilities,
        channel: .github,
        githubRepo: "Uninstaller",
        url: nil,
        bundleName: "Uninstaller",
        iconAsset: "uninstaller"
    ),
    CatalogApp(
        // Tap was App Store–only when only the watchOS / iOS apps
        // shipped. Post-desktop-port, Tap.app is a Developer-ID
        // signed Mac binary that the launcher absorbs the same way
        // as every other suite pane (libTapPane.dylib), so flip the
        // channel to .github and set the bundle name. The watchOS /
        // iOS apps continue to live at the App Store URL but the
        // launcher's row now installs / opens the Mac build.
        id: "tap",
        name: "Tap",
        tagline: "The command remote for your infrastructure.",
        category: .developerTools,
        channel: .github,
        githubRepo: "Tap",
        url: nil,
        bundleName: "Tap",
        iconAsset: "tap"
    ),
    CatalogApp(
        id: "base",
        name: "Base",
        tagline: "Universal design toolkit — monochrome, platform-agnostic.",
        category: .design,
        channel: .library,
        githubRepo: nil,
        url: "https://github.com/InfamousVague",
        bundleName: nil,
        iconAsset: "base"
    ),
    CatalogApp(
        id: "libre",
        name: "Libre",
        tagline: "Turn any technical book into an interactive course.",
        category: .learning,
        channel: .github,
        githubRepo: "Libre",
        url: nil,
        bundleName: "Libre",
        iconAsset: "libre"
    ),
]

/// Catalog grouped by category, in `AppCategory` declaration
/// order, skipping any empty buckets. Drives the sectioned list.
struct CatalogSection: Identifiable {
    var id: String { category.rawValue }
    let category: AppCategory
    let apps: [CatalogApp]
}

let CATALOG_SECTIONS: [CatalogSection] = AppCategory.allCases.compactMap {
    cat in
    let apps = CATALOG.filter { $0.category == cat }
    return apps.isEmpty ? nil : CatalogSection(category: cat, apps: apps)
}

let GITHUB_OWNER = "InfamousVague"

/// Resolved per-app state the menu row renders its action from.
struct AppStatus {
    var installed: Bool = false
    var installedVersion: String?
    var latestVersion: String?
    var downloadURL: String?
    var updatable: Bool = false
    var error: String?
}

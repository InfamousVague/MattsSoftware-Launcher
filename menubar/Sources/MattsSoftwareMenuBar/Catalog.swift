import Foundation

/// Distribution channel — mirrors the launcher's `catalog.ts` /
/// `catalog.rs` discriminant.
enum Channel: String {
    case github
    case appstore
    case dmg
    case library
}

/// One catalogued app. The presentation surface is intentionally
/// smaller than the full launcher's (a menu bar isn't a gallery) —
/// just what a row + its action needs.
struct CatalogApp: Identifiable {
    let id: String
    let name: String
    let tagline: String
    let category: String
    let channel: Channel
    /// `owner/repo` or bare `repo` (owner defaults to InfamousVague).
    let githubRepo: String?
    /// App Store / docs / direct-dmg URL depending on channel.
    let url: String?
    /// `.app` name in /Applications (no `.app`). nil = not a Mac
    /// app we install (Tap is watchOS; Base is a library).
    let bundleName: String?
}

/// The same lineup the launcher ships, sourced from the marketing
/// site's published copy. Kept in display order.
let CATALOG: [CatalogApp] = [
    CatalogApp(
        id: "blip",
        name: "Blip",
        tagline: "Your computer has been talking behind your back.",
        category: "Privacy & Security",
        channel: .github,
        githubRepo: "Blip",
        url: nil,
        bundleName: "Blip"
    ),
    CatalogApp(
        id: "vyv",
        name: "Vyv",
        tagline: "Your computer wants to sleep. Vyv disagrees.",
        category: "Utilities",
        channel: .github,
        githubRepo: "Vyv",
        url: nil,
        bundleName: "Vyv"
    ),
    CatalogApp(
        id: "diane",
        name: "Diane",
        tagline: "I'm holding in my hand a small tape recorder.",
        category: "Utilities",
        channel: .github,
        githubRepo: "Diane",
        url: nil,
        bundleName: "Diane"
    ),
    CatalogApp(
        id: "stash",
        name: "Stash",
        tagline: "Your .env files deserve a bodyguard.",
        category: "Developer Tools",
        channel: .github,
        githubRepo: "Stash",
        url: nil,
        bundleName: "Stash"
    ),
    CatalogApp(
        id: "fishbones",
        name: "Libre",
        tagline: "Turn any technical book into an interactive course.",
        category: "Learning",
        channel: .github,
        githubRepo: "Fishbones",
        url: nil,
        bundleName: "Libre"
    ),
    CatalogApp(
        id: "tap",
        name: "Tap",
        tagline: "The command remote for your infrastructure.",
        category: "Developer Tools",
        channel: .appstore,
        githubRepo: nil,
        url: "https://apps.apple.com/app/tap-command-runner/id6762214314",
        bundleName: nil
    ),
    CatalogApp(
        id: "base",
        name: "Base",
        tagline: "Universal design toolkit — monochrome, platform-agnostic.",
        category: "Design",
        channel: .library,
        githubRepo: nil,
        url: "https://github.com/InfamousVague",
        bundleName: nil
    ),
]

let GITHUB_OWNER = "InfamousVague"

/// Resolved per-app state the menu row renders its action from —
/// the Swift analogue of `catalog.rs::AppStatus`.
struct AppStatus {
    var installed: Bool = false
    var installedVersion: String?
    var latestVersion: String?
    var downloadURL: String?
    var updatable: Bool = false
    var error: String?
}

// swift-tools-version: 5.9
import PackageDescription

// MattsSoftware — the menu-bar launcher for every app I've built.
// A standalone SwiftUI executable (no Tauri, no external deps —
// Foundation + AppKit + SwiftUI only) that drops an NSStatusItem +
// transient NSPopover into the menu bar — the same shell every
// other MattsSoftware menu-bar app (Sentry, Port, Peephole, …)
// uses — and surfaces the whole catalog with one-click install /
// update / open. There is no separate window; this *is* the app.
//
// swift-tools-version 5.9 ⇒ Swift-5 language mode by default
// (Swift-6 strict concurrency would only kick in at tools-version
// 6.0+). That's deliberate: the install pipeline shells out and
// hops actors, and Swift-6 strict-concurrency would demand a lot
// of Sendable ceremony here for no runtime benefit.
let package = Package(
    name: "MattsSoftwareMenuBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MattsSoftwareMenuBar",
            path: "Sources/MattsSoftwareMenuBar",
            // The squircle app icons (+ the MattsSoftware brand
            // mark) are bundled so every catalog row shows the real
            // icon. Reached via `Bundle.module` at runtime.
            resources: [.process("Resources")]
        )
    ]
)

// swift-tools-version: 5.9
import PackageDescription

// Native Swift menu-bar companion for the MattsSoftware launcher.
// A standalone SwiftUI `MenuBarExtra` executable (no Tauri, no
// external deps — Foundation + AppKit + SwiftUI only) that mirrors
// the launcher's catalog and its install / update / open
// behaviour, so the same lineup is reachable from the menu bar
// without opening the full window.
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
            path: "Sources/MattsSoftwareMenuBar"
        )
    ]
)

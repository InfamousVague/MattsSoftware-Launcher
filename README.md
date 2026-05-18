# MattsSoftware

A menu-bar launcher for every app I've built — browse them, install
them, and keep them up to date from one place, without a window.

A standalone SwiftUI menu-bar app (`NSStatusItem` + transient
`NSPopover`, `.accessory` activation) — the same shell every other
MattsSoftware menu-bar app (Sentry, Port, Peephole, …) uses. No
Tauri, no web stack, no external dependencies: Foundation + AppKit
+ SwiftUI only.

## What it does

- **Catalog** — every shipped app (Blip, Espresso, Diane, Stash,
  Port, Peephole, Quarantine, Sentry, Alfred, Libre, Tap, Base)
  with real metadata sourced from mattssoftware.com, grouped by
  category, each row showing its real squircle icon.
- **Detect** — finds installed copies in `/Applications`, reads each
  bundle's `CFBundleShortVersionString`, and version-checks it
  against the latest GitHub release.
- **Per-app channels** — one smart action per row: GitHub Releases
  (`.dmg` download → mount → copy → detach), the Mac App Store
  (deep link), or "view source" for the Base library.
- **Install / Update / Open** — live install progress, an
  "Update all" sweep, and serialised installs (one `hdiutil`
  mount at a time). Right-click a row for reveal / reinstall /
  releases.

## Architecture

```
Package.swift                       SwiftPM executable (macOS 13+)
Sources/MattsSoftwareMenuBar/
  MattsSoftwareMenuBarApp.swift     NSStatusItem + NSPopover shell
  MenuContentView.swift             the popover panel (the whole UI)
  AppState.swift                    observable store + install queue
  Services.swift                    install pipeline, GitHub, icons
  Catalog.swift                     the app catalog (apps + channels)
  Resources/*.png                   bundled squircle icons
VERSION                             single source of the app version
icon.icns                           Finder / Login Items app icon
package.sh                          build → .app bundle (ad-hoc signed)
```

## Build

```sh
swift build                 # debug build
./package.sh                # release .app into ./dist/
./package.sh --install      # also install to /Applications
```

`./package.sh --install` replaces any prior MattsSoftware in
`/Applications`. Launch it from there, then add it under **System
Settings → General → Login Items** to keep it in your menu bar at
every login.

Apple notarization needs a paid Developer ID; `package.sh` ad-hoc
signs instead, which runs fine locally. A downloaded copy gets a
one-time right-click → Open.

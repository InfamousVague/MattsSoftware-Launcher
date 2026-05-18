# MattsSoftware

An Adobe-CC / MacPaw-style launcher for every app I've built — browse
them, install them, and keep them up to date from one place.

A single-page Tauri 2 + React TS desktop app, built on the
[Base](../../Libs/base) design system. Monochrome, icon-forward,
one settings modal.

## What it does

- **Catalog** — every shipped app (Blip, Vyv, Diane, Stash, Libre,
  Tap, Base) with real metadata sourced from the marketing site.
- **Detect** — finds installed copies in `/Applications`, reads each
  bundle's `CFBundleShortVersionString`, and version-checks it
  against the latest release.
- **Per-app channels** — installs/updates from the right source per
  app: GitHub Releases (`.dmg` download → mount → copy → detach),
  the Mac App Store (deep link), or "view source" for the Base
  library.
- **Manage** — open, reveal in Finder, or uninstall (to Trash) an
  installed app; live install progress (download → mount → copy).
- **Settings** — dark/light, chromatic accent, check-on-launch,
  launch-after-install; persisted to the app data dir.

## Architecture

```
src/                     React single-page UI (Base primitives)
  data/catalog.ts        the app catalog (real apps + channels)
  hooks/useCatalogStatus  status probe + install/open/uninstall loop
  lib/tauri.ts           typed invoke wrappers + progress events
  components/             AppCard · AppDetail · ActionButton · SettingsModal
src-tauri/src/
  catalog.rs             installed-detection + GitHub latest-release
  install.rs             dmg install / open / reveal / uninstall (+ progress events)
  settings.rs            persisted launcher preferences
```

## Develop

```sh
npm install
npm run tauri:dev      # Tauri dev shell (Vite on :1420)
npm run build          # tsc + vite build
npm run tauri:build    # packaged .app
```

The Base design system is consumed as raw source via the
`file:../../Libs/base` dependency (npm symlinks it into
`node_modules/@mattmattmattmatt/base`); the `@base` Vite alias +
tsconfig path + `server.fs.allow` entry wire it up — same setup as
Libre.academy.

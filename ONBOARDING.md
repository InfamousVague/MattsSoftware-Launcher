# MattsSoftware — Deploy & Fork Context

The operational map for every app on **mattssoftware.com**: what each
app is, how it's built / signed / notarized / released, the Apple
infra, and the hard-won gotchas. Start here before changing or
shipping anything, and when prompting a fork to add a feature to an
existing app.

---

## 1. The portfolio

Apps live as sibling dirs under `~/Development/Apps/`. The launcher
repo (`mattssoftware-launcher`) is the hub.

| App | Local dir | GitHub repo | Type | Bundle id | Channel |
|---|---|---|---|---|---|
| **MattsSoftware** (the launcher) | `mattssoftware-launcher` | `InfamousVague/MattsSoftware-Launcher` | Swift menu-bar (SwiftPM) | `com.mattssoftware.launcher` | GitHub release `.dmg` + OTA self-update |
| Alfred | `Alfred` | `InfamousVague/Alfred` | Swift menu-bar | — | GitHub `.dmg` |
| Quarantine | `quarantine-swift` | `InfamousVague/Quarantine` | Swift menu-bar | — | GitHub `.dmg` |
| Espresso | `espresso-swift` | `InfamousVague/Espresso` | Swift menu-bar | — | GitHub `.dmg` |
| Sentry | `sentry-swift` | `InfamousVague/Sentry` | Swift menu-bar | — | GitHub `.dmg` |
| Peephole | `peephole-swift` | `InfamousVague/Peephole` | Swift menu-bar | — | GitHub `.dmg` |
| Port | `port-swift` | `InfamousVague/Port` | Swift menu-bar | — | GitHub `.dmg` |
| Blip | `Blip` | `InfamousVague/Blip` | Tauri (+ Network Extension) | `com.infamousvague.blip` | GitHub `.dmg` via **local `make all` + manual upload** (CI can't build it — see §6.10) |
| Diane | `diane` | `InfamousVague/Diane` | Tauri | `com.mattssoftware.diane` | GitHub `.dmg` |
| Stash | `stash` | `InfamousVague/Stash` | Tauri (+ relay, watch, mobile, StashBar) | `com.mattssoftware.stash` | GitHub `.dmg` |
| Libre | `Libre.academy` | `InfamousVague/Libre.academy` | Tauri | `com.mattssoftware.libre` | GitHub `.dmg` via **CI** + Tauri OTA |
| Tap | `tap` | App Store | watchOS/iOS | — | Mac App Store |
| Base | (Libs/base) | `InfamousVague/base` | React library | — | not distributed |

Repo-rename chain: **Fishbones → Libre → Libre.academy**. GitHub 301s
chain-resolve and both `gh` and `URLSession` follow them, so the
launcher catalog's `githubRepo: "Libre"` resolves fine.

---

## 2. The cardinal rule for "install / download"

The launcher reads `api.github.com/repos/InfamousVague/<repo>/releases/latest`
and looks for an asset ending in **`.dmg`**. The marketing site links
to `/releases/latest`. **If a release has no notarized `.dmg`, the app
is uninstallable from the launcher and undownloadable from the site**,
even though everything else looks fine. Diane/Stash/Libre were all
broken purely because their releases shipped with no macOS `.dmg`.
Every release MUST attach a signed+notarized `.dmg`.

---

## 3. Apple signing infrastructure (no setup needed — already live)

- Apple Developer Program, **Team `F6ZAL7ANAD`** (Matt Wisniewski).
- **Developer ID Application** cert, hash
  `0948896DC970503ADEF5B5070E0BB3E9D9047757` — used by every app for
  notarized, non-App-Store distribution.
- **`Notary`** = a `notarytool` keychain profile already stored on the
  build machine. Local notarization is `xcrun notarytool submit … 
  --keychain-profile Notary --wait` then `xcrun stapler staple`. Zero
  config; proven across dozens of submissions.
- Tauri repos that notarize locally read **`.env.apple`** (gitignored;
  holds `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_PASSWORD`
  app-specific, `APPLE_TEAM_ID`). Diane instead uses the `Notary`
  profile (no `.env.apple`).
- CI-notarizing repos (Blip, Libre) need these **GitHub repo
  secrets**: `APPLE_CERTIFICATE` (base64 .p12), `APPLE_CERTIFICATE_PASSWORD`,
  `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_PASSWORD`,
  `APPLE_TEAM_ID`, `TAURI_SIGNING_PRIVATE_KEY`,
  `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`. Exporting the .p12 from the
  keychain requires an **interactive GUI approval** — it cannot be
  done headlessly.
- **Mac App Store is out of scope.** It mandates the App Sandbox,
  which strips the capabilities these system tools need; the launcher
  itself is permanently MAS-ineligible (it installs other apps —
  guideline 2.5.2). Everything stays Developer ID + notarized.

---

## 4. How each app is built & released

### Swift menu-bar suite (Alfred, Quarantine, Espresso, Sentry, Peephole, Port, MattsSoftware)
Orchestrated from the **launcher repo**:
```
cd mattssoftware-launcher
make versions                 # every app's version
make build                    # build+sign+notarize+staple all 7
make release                  # build + commit bump + push + GH release (all 7)
make ship                     # bump + release (all 7)
make build-Sentry             # one app (also bump-/release-<App>)
```
`scripts/suite.sh` is the engine; each suite app has
`scripts/make-app.sh` (Developer-ID sign + `Notary` notarize +
staple). The launcher itself uses `./package.sh` + a `VERSION` file
and is the `MattsSoftware` entry in `suite.sh`. Per-app ship is
`make bump-<App> && make release-<App>` (there is no `ship-<App>`).

### Tauri apps — each its own repo + Makefile
```
cd <app>
make local-release            # bump → build → sign → notarize → upload .dmg (LOCAL)
make release                  # bump → commit → tag → push  (CI builds it)
make notarize                 # notarize+staple an existing build
```
- **Diane**: `make local-release`/`notarize` use the `Notary`
  keychain profile (no `.env.apple`). `src-tauri/scripts/post-build.sh`
  + `Makefile` were added in this effort.
- **Stash / Libre**: `make local-release` uses `.env.apple`. Both
  also have a `post-build.sh` (hardened-runtime re-sign + rebuild
  DMG).
- **Blip**: `.github/workflows/release.yml` exists but **CI builds
  fail** (§6.10) — Blip is released **locally**: `cd Blip && make all`
  (build NE + Tauri, sign, notarize, install), then
  `gh release create v<ver> <dmg> --latest`. `make local-release`
  does bump+all+tag+push+release in one shot but **double-bumps** if
  you already tagged via `make release` — prefer `make all` + manual
  `gh release create` for an already-tagged version. Blip commits
  its prebuilt NE binaries (`src-tauri/resources/blip-ne-*`,
  `libblip_ne_bridge.dylib`, the `.systemextension`) — intentional.
- **Libre**: `.github/workflows/desktop-build.yml` — matrix builds
  Linux/Windows on tag push; a dedicated **`macos-release`** job
  (added in this effort) builds + Developer-ID signs + runs
  `post-build.sh` + notarizes + staples + uploads the Mac `.dmg`,
  then `build-update-manifest` rebuilds `latest.json`. Needs the 6
  Apple secrets above on the repo.

### Launcher OTA self-update
`MattsSoftware` is its own first catalog entry (`Catalog.swift`,
category `.launcher`). When a newer `MattsSoftware-Launcher` release
exists, the row shows **Update**; `Services.selfUpdate` downloads +
mounts, then a detached shell helper waits for the app to exit,
`ditto`s the new bundle over `/Applications/MattsSoftware.app`, and
relaunches. So shipping a launcher fix = `make bump-MattsSoftware &&
make release-MattsSoftware`; users get it via the tray.

---

## 5. Launcher (MattsSoftware) internals

SwiftUI menu-bar app: `Bootstrap` entry → `MattsSoftwareMenuBarApp`
(`NSStatusItem` + transient `NSPopover`, `.accessory`).
- `Catalog.swift` — the app list + `AppStatus`. `Services.swift` —
  GitHub lookup (disk cache + ETag + token + last-known-good),
  install pipeline (download → `hdiutil attach` → `ditto` →
  `detach`), `selfUpdate`, `forceQuit`, `trashApp`, icon loading.
  `AppState.swift` — observable store, FIFO install queue,
  quit→install→relaunch, uninstall. `MenuContentView.swift` — the
  popover UI (sectioned rows, smart action, Uninstall).
- **Headless self-tests** (env-gated, ship inert):
  `MS_ICON_TEST=1 <binary>` (icons resolve w/o Bundle.module),
  `MS_INSTALL_TEST=<id> <binary>` (full install pipeline under the
  real signed bundle).
- `./package.sh` assembles the `.app` (icons copied **flat into
  Contents/Resources**, never SwiftPM resources), Developer-ID
  signs, notarizes, staples; `--install` replaces `/Applications`.
- GitHub rate limiting: persistent `~/Library/Caches/com.mattssoftware.launcher/releases.json`
  + conditional `If-None-Match` (304s are free) + optional
  `GITHUB_TOKEN` / `~/.config/mattssoftware/github-token`.

---

## 6. Gotchas — do not relearn these the hard way

1. **`hdiutil attach -quiet` prints nothing** → the mountpoint
   parser starves and every install fails "could not parse
   mountpoint". No `-quiet` on attach (keep it on detach).
2. **`Bundle(path:)` is process-cached.** After an in-place update
   it reports the *old* `CFBundleShortVersionString` forever, so the
   row stays on "Update". Read `Contents/Info.plist` off disk every
   time.
3. **SwiftPM `Bundle.module` `fatalError`s** in a hand-assembled
   `.app` (it only checks the app root + a hardcoded dev `.build`
   path). Don't declare SwiftPM `resources:`; copy assets into
   `Contents/Resources` and load via `Bundle.main` (nil, never
   crash).
4. **Ad-hoc signed apps are Gatekeeper-rejected on other Macs** and
   SwiftPM `Bundle.module` crashes there. Always Developer-ID sign +
   notarize + staple for anything that leaves this machine.
5. A release with **no `.dmg`** = uninstallable/undownloadable (see
   §2). Diane/Stash had releases with zero assets; Libre had only
   Linux/Windows.
6. **`make release` builds the working tree.** A dirty repo ships
   uncommitted WIP. Commit deliberately first; `suite.sh release`
   only stages the version-bearing file by design — never sweep
   unrelated WIP.
7. **Big untracked dirs**: Stash's `mobile/` (Expo, Pods 153M) and
   `native/StashBar/` (`.build` 176M) — only source is committed;
   artifacts stay gitignored. Never blind-`git add` a mega-dir.
8. **`.env.apple` is secret** (gitignored, app-specific password).
   Never commit or echo it.
9. Repo-rename 301s work but point catalog/scripts at the canonical
   name where practical.
10. **Blip CI cannot build a release.** `tauri-build`'s build script
    validates every `bundle.resources` entry; Blip declares huge
    geo/map files (`planet.pmtiles` 104M, `ocean.pmtiles` 78M,
    `GeoLite2-City.mmdb` 61M, `dbip-city-lite.mmdb` 125M, …) that are
    **not in git** (too big), so the CI checkout is missing them and
    the build script exits 1 ("failed to run custom build command
    for `app`"). Both v0.4.6 and v0.4.7 CI runs failed this way; the
    shipped dmgs came from local builds. Always release Blip locally
    (the resources live on the maintainer's machine). Don't "fix" CI
    by committing 370MB of tiles.

---

## 7. Commit conventions

- **Never** add a `Co-Authored-By: Claude` trailer — commits look
  like the user wrote them. (Also: gpg signing is disabled per-commit
  with `-c commit.gpgsign=false` when running non-interactively.)
- Stage **specific files**, not `git add -A`, so WIP / secrets /
  artifacts don't sneak in.
- Conventional, imperative subject; body explains the *why*.

---

## 8. Adding a feature to an existing app (the fork workflow)

1. `cd ~/Development/Apps/<dir>` (see §1 table).
2. Build/run locally — Swift: `swift build` / `./package.sh`; Tauri:
   `npm run tauri dev` / `make build`.
3. Commit the change (only the relevant files; conventions §7).
4. Release with that app's command (§4 table). Confirm the GitHub
   release has a **notarized `.dmg`** (`spctl -a -vv`, `stapler
   validate`).
5. The launcher and marketing site pick it up automatically from
   `/releases/latest`. Launcher fixes additionally need a launcher
   release so users get them via OTA.
6. **Blocked-by-WIP / failed-CI / no-Mac-dmg** are the three things
   that silently break a release — check them first when "an app
   won't install/update".

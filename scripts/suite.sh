#!/usr/bin/env bash
#
# Build / bump / release the whole MattsSoftware menu-bar suite from
# one place. Driven by the repo Makefile (see `make help`), but also
# runnable directly:
#
#   scripts/suite.sh versions
#   scripts/suite.sh build  Sentry Port      # subset
#   scripts/suite.sh release                 # all 7
#
# The sibling app repos are expected to sit next to this one:
#   ../Alfred ../quarantine-swift ../espresso-swift ../sentry-swift
#   ../peephole-swift ../port-swift   (+ this launcher repo itself)
#
# Each swift app self-signs + notarizes + staples + builds its .dmg
# via its own scripts/make-app.sh (the .dmg now wraps an already-
# stapled .app). The launcher uses package.sh; its .dmg is assembled
# here from the stapled dist/ app. Releases only ever stage the
# version-bearing file — never sweeps unrelated working-tree WIP.
#
# bash 3.2 compatible (the macOS system bash): no mapfile, no
# associative arrays.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"   # launcher repo root
SIGN_IDENTITY="${SIGN_IDENTITY:-0948896DC970503ADEF5B5070E0BB3E9D9047757}"

# key | dir (relative to launcher root) | GitHub repo
APPS=(
  "Alfred|../Alfred|InfamousVague/Alfred"
  "Quarantine|../quarantine-swift|InfamousVague/Quarantine"
  "Espresso|../espresso-swift|InfamousVague/Espresso"
  "Sentry|../sentry-swift|InfamousVague/Sentry"
  "Peephole|../peephole-swift|InfamousVague/Peephole"
  "Port|../port-swift|InfamousVague/Port"
  "StickyKeys|../stickykeys-swift|InfamousVague/StickyKeys"
  "Stats|../stats-swift|InfamousVague/Stats"
  "Uninstaller|../uninstaller-swift|InfamousVague/Uninstaller"
  "Worktree|../worktree-swift|InfamousVague/Worktree"
  "Halo|../halo-swift|InfamousVague/Halo"
  # Tap's macOS port lives in the cross-platform monorepo at
  # tap/macos/, not its own peer Swift package — point at the
  # subdir directly so suite.sh's bump/build/release dispatch
  # reaches its own scripts/make-app.sh.
  "Tap|../tap/macos|InfamousVague/Tap"
  "MattsSoftware|.|InfamousVague/MattsSoftware-Launcher"
)

keys() { local r; for r in "${APPS[@]}"; do echo "${r%%|*}"; done; }

_row() {  # echo "dir|repo" for <key>, or fail
  local r k d g
  for r in "${APPS[@]}"; do
    IFS='|' read -r k d g <<<"$r"
    if [ "$k" = "$1" ]; then echo "$d|$g"; return 0; fi
  done
  echo "unknown app: $1" >&2; return 1
}
appdir()  { local rd; rd="$(_row "$1")"; echo "$HERE/${rd%%|*}"; }
apprepo() { local rd; rd="$(_row "$1")"; echo "${rd##*|}"; }

ver() {  # current version of <key>
  local k="$1" d; d="$(appdir "$k")"
  if [ "$k" = MattsSoftware ]; then
    tr -d ' \n' < "$d/VERSION"
  else
    grep -m1 'VERSION=' "$d/scripts/make-app.sh" \
      | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/'
  fi
}

bump() {  # bump <key> — patch by default, semver-minor via BUMP=minor
  local k="$1" d cur new; d="$(appdir "$k")"
  cur="$(ver "$k")"
  case "${BUMP:-patch}" in
    minor) new="$(awk -F. '{printf "%d.%d.0", $1, $2 + 1}' <<<"$cur")" ;;
    patch) new="$(awk -F. '{printf "%d.%d.%d", $1, $2, $3 + 1}' <<<"$cur")" ;;
    *) echo "unknown BUMP level: $BUMP (use patch | minor)" >&2; return 1 ;;
  esac
  if [ "$k" = MattsSoftware ]; then
    printf '%s\n' "$new" > "$d/VERSION"
  else
    sed -i '' -E "s/^VERSION=\"[0-9.]+\"/VERSION=\"$new\"/" \
      "$d/scripts/make-app.sh"
  fi
  echo "▸ $k  $cur → $new"
}

build() {  # build + Developer ID sign + notarize + staple <key>
  local k="$1" d; d="$(appdir "$k")"
  echo "════════ build $k ($(ver "$k")) ════════"
  if [ "$k" = MattsSoftware ]; then
    ( cd "$d" && ./package.sh )
  else
    ( cd "$d" && bash scripts/make-app.sh )
  fi
}

_launcher_dmg() {  # wrap the stapled dist app into a signed .dmg, echo its path
  local d v dmg stage; d="$(appdir MattsSoftware)"; v="$(ver MattsSoftware)"
  dmg="$d/MattsSoftware-$v.dmg"
  stage="$(mktemp -d)/d"; mkdir -p "$stage"
  cp -R "$d/dist/MattsSoftware.app" "$stage/MattsSoftware.app"
  ln -s /Applications "$stage/Applications"
  rm -f "$dmg"
  hdiutil create -quiet -volname MattsSoftware -srcfolder "$stage" \
    -ov -format UDZO "$dmg" >/dev/null
  if security find-identity -v -p codesigning 2>/dev/null \
       | grep -q "$SIGN_IDENTITY"; then
    codesign --force --sign "$SIGN_IDENTITY" "$dmg" >/dev/null 2>&1 || true
  fi
  echo "$dmg"
}

dmgpath() {  # absolute .dmg path for <key> at its current version
  local k="$1" d v; d="$(appdir "$k")"; v="$(ver "$k")"
  if [ "$k" = MattsSoftware ]; then echo "$d/MattsSoftware-$v.dmg"
  else echo "$d/$k-$v.dmg"; fi
}

release() {  # build → commit the bump → push → GitHub release <key>
  local k="$1" d repo v dmg notes
  d="$(appdir "$k")"; repo="$(apprepo "$k")"
  build "$k"
  v="$(ver "$k")"
  if [ "$k" = MattsSoftware ]; then dmg="$(_launcher_dmg)"
  else dmg="$(dmgpath "$k")"; fi
  if [ ! -f "$dmg" ]; then echo "✗ $k: expected $dmg, not found" >&2; return 1; fi

  (
    cd "$d"
    if [ "$k" = MattsSoftware ]; then
      git add VERSION package.sh
    else
      git add scripts/make-app.sh
    fi
    git commit -m "chore(build): release v$v" >/dev/null 2>&1 \
      || echo "  (version unchanged — nothing to commit)"
    git push origin HEAD
  )

  notes="$k $v — Developer ID signed + Apple-notarized, with the
notarization ticket stapled to the app so it opens on any Mac
(no \"unidentified developer\" prompt), even offline. Open the
.dmg and drag $k.app to /Applications."

  if gh release create "v$v" "$dmg" --repo "$repo" \
       --title "$k $v" --notes "$notes" --latest 2>/dev/null; then
    :
  else
    echo "  (release v$v exists — refreshing the asset)"
    gh release upload "v$v" "$dmg" --repo "$repo" --clobber
    gh release edit   "v$v" --repo "$repo" --latest >/dev/null
  fi
  echo "✓ $k v$v  →  https://github.com/$repo/releases/tag/v$v"
}

clean() {
  local k d
  for k in $(keys); do
    d="$(appdir "$k")"
    if [ "$k" = MattsSoftware ]; then
      rm -rf "$d/dist" "$d"/MattsSoftware-*.dmg
    else
      rm -rf "$d/$k.app" "$d"/"$k"-*.dmg
    fi
  done
  echo "✓ cleaned build artifacts"
}

versions() {
  local k
  for k in $(keys); do printf "%-14s %s\n" "$k" "$(ver "$k")"; done
}

main() {
  local cmd="${1:-}"; shift || true
  local sel
  if [ "$#" -eq 0 ]; then sel=$(keys); else sel="$*"; fi
  case "$cmd" in
    build)    for k in $sel; do build   "$k"; done ;;
    bump)     for k in $sel; do bump    "$k"; done ;;
    release)  for k in $sel; do release "$k"; done ;;
    versions) versions ;;
    clean)    clean ;;
    *) echo "usage: suite.sh {build|bump|release|versions|clean} [App …]" >&2
       echo "apps:  $(keys | tr '\n' ' ')" >&2
       exit 2 ;;
  esac
}
main "$@"

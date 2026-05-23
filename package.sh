#!/usr/bin/env bash
#
# Package MattsSoftware into a real, double-clickable,
# login-item-able .app bundle.
#
# MattsSoftware is a menu-bar launcher: the SwiftPM target builds a
# bare executable that runs (it flips to .accessory at launch) but
# isn't something a user can keep — no Finder identity, no icon, no
# "Open at Login" entry. This wraps the release binary + its
# SwiftPM resource bundle in a proper LSUIElement app so it's a
# first-class, installable artifact.
#
#   ./package.sh            → builds .app into ./dist/
#   ./package.sh --install  → also installs it to /Applications
#                             (replacing any prior MattsSoftware)
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MattsSoftware"
BIN_NAME="MattsSoftwareMenuBar"
BUNDLE_ID="com.mattssoftware.launcher"
VERSION="$(tr -d ' \n' < VERSION 2>/dev/null || echo "0.1.0")"
# Developer ID so the launcher can be notarized like the rest of
# the menu-bar suite. Override with SIGN_IDENTITY=- for a purely
# local ad-hoc build (no notarization possible in that mode).
SIGN_IDENTITY="${SIGN_IDENTITY:-0948896DC970503ADEF5B5070E0BB3E9D9047757}"
NOTARY_PROFILE="${NOTARY_PROFILE:-Notary}"

echo "▸ Building release binary…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="dist/${APP_NAME}.app"
echo "▸ Assembling ${APP} (v${VERSION})…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"

# Embed the shared SuiteKit contract. Every feature framework the
# launcher loads at runtime (out of an installed app) resolves its
# @rpath/libSuiteKit.dylib against THIS copy — dyld dedupes by
# install name — so there's one shared SuitePane identity. The
# rpath lets the bundled exe find it under Contents/Frameworks.
mkdir -p "$APP/Contents/Frameworks"
cp "$BIN_DIR/libSuiteKit.dylib" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath @executable_path/../Frameworks \
  "$APP/Contents/MacOS/$BIN_NAME" 2>/dev/null || true

# Row icons: copy the source PNGs straight into Contents/Resources
# so the app loads them via Bundle.main. We deliberately do NOT use
# SwiftPM's resource bundle — its generated Bundle.module accessor
# fatalErrors when the bundle isn't found, and in a hand-assembled
# .app it only ever resolved via a hardcoded dev `.build` path, so
# the app crashed on first popover render on every other machine.
cp Sources/MattsSoftwareMenuBar/Resources/*.png \
   "$APP/Contents/Resources/"

# The MattsSoftware mark in Finder / Login Items / the about box.
if [ -f "icon.icns" ]; then
  cp "icon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>${BIN_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <!-- Used by the Uninstaller pane (when merged into the launcher)
       so Finder can move /Applications/<App>.app to Trash on the
       launcher's behalf. First uninstall triggers a one-time
       "MattsSoftware would like to control Finder" prompt. -->
  <key>NSAppleEventsUsageDescription</key>
  <string>MattsSoftware asks Finder to move apps and their leftover files to the Trash on your behalf when you use the Uninstaller pane.</string>
  <!-- Desktop widget tap targets. Each pane's WidgetKit view
       carries a `.widgetURL(URL(\"mattssoftware://<paneId>\"))`
       so clicking it opens the launcher's popover with that
       pane already selected. The launcher's AppDelegate's
       `application(_:open:)` parses the host segment as the
       pane id and routes via SuiteHost.openMerged + showPopover.
       Without this URL types block macOS doesn't know which
       app handles \`mattssoftware://\` and the widget tap is a no-op. -->
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>com.mattssoftware.launcher.url</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>mattssoftware</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Sign with the Developer ID + hardened runtime + secure timestamp
# so the bundle is notarizable (ad-hoc apps cannot be notarized).
# Order matters: strip xattr detritus first (cp leaves Finder attrs
# codesign rejects), sign the inner binary, then the wrapper — NO
# --deep (it chokes on the resource-only .bundle in
# Contents/Resources). Two passes because the freshly cp -R'd
# resource bundle sometimes still carries a Finder xattr on the
# first pass. Falls back to ad-hoc when SIGN_IDENTITY=- or the
# Developer ID cert is absent (local-only; not notarizable).
SIGNED_DEVID=0
# Launcher host entitlements — Sign in with Apple (needed when a
# merged pane like Tap calls ASAuthorizationAppleIDProvider in our
# process; without this the SIWA flow fails with error 1000).
HOST_ENT="$(dirname "$0")/MattsSoftware.entitlements"
sign_app() {
  local i
  if [ "$SIGN_IDENTITY" != "-" ] \
     && security find-identity -v -p codesigning 2>/dev/null \
        | grep -q "$SIGN_IDENTITY"; then
    for i in 1 2; do
      xattr -cr "$APP" 2>/dev/null || true
      codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" \
        "$APP/Contents/Frameworks/libSuiteKit.dylib" \
        >/dev/null 2>&1 || true
      if codesign --force --options runtime --timestamp \
           --entitlements "$HOST_ENT" \
           --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/$BIN_NAME" \
           >/dev/null 2>&1 \
         && codesign --force --options runtime --timestamp \
              --entitlements "$HOST_ENT" \
              --sign "$SIGN_IDENTITY" "$APP" >/dev/null 2>&1 \
         && codesign --verify --strict "$APP" >/dev/null 2>&1; then
        SIGNED_DEVID=1
        return 0
      fi
    done
  fi
  # Ad-hoc fallback (local-only; cannot be notarized).
  for i in 1 2; do
    xattr -cr "$APP" 2>/dev/null || true
    codesign --force --sign - \
      "$APP/Contents/Frameworks/libSuiteKit.dylib" \
      >/dev/null 2>&1 || true
    if codesign --force --sign - "$APP" >/dev/null 2>&1 \
       && codesign --verify --strict "$APP" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}
if sign_app; then
  if [ "$SIGNED_DEVID" = "1" ]; then
    echo "✓ Built + Developer ID signed $APP"
  else
    echo "✓ Built + ad-hoc signed $APP (local only — not notarizable)"
  fi
else
  echo "✓ Built $APP (unsigned — runs locally, may prompt on"
  echo "  first launch from /Applications: right-click → Open)"
fi

# ── Notarize + staple (only when Developer ID signed) ─────────────
# Staples the ticket onto the .app so the installed copy is
# Gatekeeper-trusted offline. Non-fatal: a creds-less / rejected
# build still completes, just signed-only. Runs BEFORE --install so
# the copy placed in /Applications is the stapled one.
if [ "$SIGNED_DEVID" = "1" ]; then
  echo "▸ Notarizing $APP (waits on Apple)…"
  NZIP="$(mktemp -d)/notarize.zip"
  ditto -c -k --keepParent "$APP" "$NZIP"
  if xcrun notarytool submit "$NZIP" \
       --keychain-profile "$NOTARY_PROFILE" --wait; then
    if xcrun stapler staple "$APP"; then
      if xcrun stapler validate "$APP"; then
        echo "✓ notarized + stapled $APP"
      else
        echo "⚠ staple validate failed for $APP"
      fi
    else
      echo "⚠ stapling failed for $APP"
    fi
  else
    echo "⚠ notarization skipped/failed — $APP signed but not notarized"
  fi
fi

if [ "${1:-}" = "--install" ]; then
  DEST="/Applications/${APP_NAME}.app"
  echo "▸ Installing to ${DEST}…"
  # Quit any running instance so the copy isn't racing a live
  # binary, then clear the prior bundle AND the legacy
  # "MattsSoftware Menu Bar.app" identity this replaces.
  pkill -x "$BIN_NAME" 2>/dev/null || true
  sleep 1
  rm -rf "$DEST" "/Applications/MattsSoftware Menu Bar.app"
  cp -R "$APP" "$DEST"
  echo "✓ Installed. Launch it from /Applications, then add it"
  echo "  under System Settings → General → Login Items to keep"
  echo "  MattsSoftware in your menu bar at every login."
fi

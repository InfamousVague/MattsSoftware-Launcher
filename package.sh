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
RES_BUNDLE="MattsSoftwareMenuBar_MattsSoftwareMenuBar.bundle"
VERSION="$(tr -d ' \n' < VERSION 2>/dev/null || echo "0.1.0")"

echo "▸ Building release binary…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="dist/${APP_NAME}.app"
echo "▸ Assembling ${APP} (v${VERSION})…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"

# Inside a .app, SwiftPM's `Bundle.module` resolves against
# `Bundle.main.resourceURL` (= Contents/Resources), so the resource
# bundle goes there and *only* there. Putting it next to the binary
# in Contents/MacOS makes `codesign --deep` choke on it as an
# unsignable subcomponent.
if [ -d "$BIN_DIR/$RES_BUNDLE" ]; then
  cp -R "$BIN_DIR/$RES_BUNDLE" "$APP/Contents/Resources/$RES_BUNDLE"
fi

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
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper lets it run locally without a
# quarantine nag (no Developer ID needed for a personal app).
# Order matters: strip xattr detritus first (cp leaves Finder attrs
# that codesign rejects), then ONE plain sign of the wrapper — no
# --deep and no pre-signing the inner binary, both of which trip on
# the resource-only .bundle in Contents/Resources.
sign_app() {
  # Two attempts: the freshly cp -R'd resource bundle sometimes
  # still has Finder xattrs on the first pass that codesign rejects
  # ("resource fork … not allowed"); a second xattr-strip + sign
  # then takes cleanly.
  local i
  for i in 1 2; do
    xattr -cr "$APP" 2>/dev/null || true
    if codesign --force --sign - "$APP" >/dev/null 2>&1 \
       && codesign --verify --strict "$APP" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}
if sign_app; then
  echo "✓ Built + ad-hoc signed $APP"
else
  echo "✓ Built $APP (unsigned — runs locally, may prompt on"
  echo "  first launch from /Applications: right-click → Open)"
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

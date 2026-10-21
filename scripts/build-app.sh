#!/usr/bin/env bash
# build-app.sh — assemble a proper FreeTubeInstaller.app bundle from the
# Swift package, ad-hoc code-sign it, and (optionally) install to ~/Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="FreeTubeInstaller"
BUNDLE_ID="local.freetube.installer"
VERSION="${VERSION:-1.1.0}"
OUT="${OUT_DIR:-$ROOT/dist}"
INSTALL_TO_HOME="${1:-}"

echo "▶ Building release binary (Swift package)…"
swift build -c release --product "$APP_NAME"

BIN="$(swift build -c release --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN" ]]; then
  echo "✗ Binary not found at $BIN" >&2
  exit 1
fi

APP="$OUT/$APP_NAME.app"
echo "▶ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>FreeTube Music Add-On</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>FreeTube Music Add-On — GPL-3.0</string>
</dict>
</plist>
PLIST

echo "▶ Ad-hoc code signing…"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "⚠ codesign skipped (non-fatal)"

if [[ "$INSTALL_TO_HOME" == "--install" ]]; then
  DEST="$HOME/Applications/$APP_NAME.app"
  echo "▶ Installing to $DEST"
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
  echo "✓ Installed. Open it from Finder or: open \"$DEST\""
fi

echo "✓ Done: $APP"

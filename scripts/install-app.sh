#!/usr/bin/env bash
# install-app.sh — install a downloaded (or built) FreeTubeInstaller.app to
# ~/Applications and clear the Gatekeeper quarantine flag so macOS lets it run.
#
# FreeTubeInstaller is ad-hoc signed (it has no paid Apple Developer ID, exactly
# like FreeTube's own macOS releases), so Gatekeeper blocks it on first launch.
# This script removes the quarantine attribute, re-signs ad-hoc for Apple Silicon,
# and opens the app — no right-click → Open needed.
#
# Usage:
#   ./install-app.sh                      # expects FreeTubeInstaller.app next to it
#   ./install-app.sh /path/to/FreeTubeInstaller.app
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_SRC=""
if [[ $# -ge 1 ]]; then
  APP_SRC="$1"
else
  APP_SRC="$SELF_DIR/FreeTubeInstaller.app"
fi

if [[ ! -d "$APP_SRC" ]]; then
  echo "FreeTubeInstaller.app not found at: $APP_SRC" >&2
  echo "Usage: install-app.sh /path/to/FreeTubeInstaller.app" >&2
  exit 1
fi

DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/FreeTubeInstaller.app"

echo "▶ Installing FreeTubeInstaller to $DEST"
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
cp -R "$APP_SRC" "$DEST"

# Remove the Gatekeeper quarantine flag (the app is ad-hoc signed, like FreeTube).
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# Re-sign ad-hoc so Apple Silicon accepts it without a "damaged" warning.
codesign --force --deep --sign - "$DEST" >/dev/null 2>&1 || true

echo "✓ Installed and de-quarantined: $DEST"
echo "▶ Launching…"
open "$DEST"

#!/usr/bin/env bash
# Install FreeTube on macOS, verify its SHA-256 digest, restore config, and
# set up the checksum-verified auto-updater.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="https://api.github.com/repos/FreeTubeApp/FreeTube/releases"

VERSION="latest"
APP_DIR="$HOME/Applications"
SYSTEM_INSTALL=0
RESTORE_CONFIG=1
LAUNCH=1
MENU_BAR_NOW_PLAYING=0
CONFIG_DIR=""

usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Installs the official FreeTube macOS release (SHA-256 verified) and sets up an
auto-updater (login + every 6 hours).

Options:
  --version VERSION    Pin a version, e.g. 0.25.3 (default: latest)
  --system             Install to /Applications (requires sudo); auto-update is
                       then unavailable because replacing needs admin rights
  --no-config          Skip restoring a config snapshot
  --config-dir DIR     Config snapshot to restore (default: ../freetube-configs-main)
  --menu-bar-now-playing  Show the macOS Now Playing item in the menu bar
  --no-launch          Do not open FreeTube when finished
  -h, --help           Show this help
USAGE
}

while (($#)); do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --system) SYSTEM_INSTALL=1; shift ;;
    --no-config) RESTORE_CONFIG=0; shift ;;
    --config-dir) CONFIG_DIR="$2"; shift 2 ;;
    --menu-bar-now-playing) MENU_BAR_NOW_PLAYING=1; shift ;;
    --no-launch) LAUNCH=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer targets macOS." >&2
  exit 1
fi

for cmd in curl python3 hdiutil ditto codesign shasum xattr; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd" >&2; exit 1; }
done

if ((SYSTEM_INSTALL)); then
  APP_DIR="/Applications"
  if [[ ! -w "$APP_DIR" ]]; then
    echo "No write access to /Applications; the installer will prompt via sudo." >&2
  fi
fi

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) SUFFIX="arm64" ;;
  x86_64) SUFFIX="x64" ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

# Resolve the release.
if [[ "$VERSION" == "latest" ]]; then
  API_URL="$API?per_page=1"
else
  NORMALIZED="$(printf '%s' "$VERSION" | sed 's/^v//; s/-beta$//')"
  API_URL="$API/tags/v${NORMALIZED}-beta"
fi

echo "Resolving FreeTube release…"
RELEASE_JSON="$(curl -fsSL --retry 3 --connect-timeout 20 -H 'Accept: application/vnd.github+json' "$API_URL")"

PARSED="$(printf '%s' "$RELEASE_JSON" | python3 -c '
import json, sys
raw = json.load(sys.stdin)
rel = raw[0] if isinstance(raw, list) else raw
tag = rel.get("tag_name", "")
ver = tag.lstrip("v").replace("-beta", "")
want = "freetube-%s-beta-mac-%s.dmg" % (ver, sys.argv[1])
for a in rel.get("assets", []):
    if a.get("name") == want:
        digest = (a.get("digest") or "").replace("sha256:", "")
        print("\t".join([tag, ver, want, a.get("browser_download_url", ""), digest]))
        break
' "$SUFFIX")"

if [[ -z "$PARSED" ]]; then
  echo "No macOS $SUFFIX DMG found for the requested release." >&2
  exit 1
fi

IFS=$'\t' read -r TAG VER ASSET_NAME ASSET_URL DIGEST <<< "$PARSED"

if [[ -z "$DIGEST" ]]; then
  echo "Release $TAG has no published SHA-256 digest; refusing to install." >&2
  exit 1
fi

echo "Installing FreeTube $VER ($ASSET_NAME)"

# Quit a running copy so we can replace the bundle.
if pgrep -f "FreeTube.app/Contents/MacOS/FreeTube" >/dev/null 2>&1; then
  echo "Quitting FreeTube…"
  osascript -e 'tell application "FreeTube" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    pgrep -f "FreeTube.app/Contents/MacOS/FreeTube" >/dev/null 2>&1 || break
    sleep 0.5
  done
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/freetube-install.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
DMG="$TMP/$ASSET_NAME"

echo "Downloading…"
curl -fL --retry 3 --connect-timeout 20 -o "$DMG" "$ASSET_URL"

ACTUAL="$(shasum -a 256 "$DMG" | awk '{print $1}')"
if [[ "$(printf '%s' "$ACTUAL" | tr 'A-F' 'a-f')" != "$(printf '%s' "$DIGEST" | tr 'A-F' 'a-f')" ]]; then
  echo "Checksum mismatch! expected $DIGEST, got $ACTUAL" >&2
  exit 1
fi
echo "Checksum verified."

mkdir -p "$TMP/mnt"
hdiutil attach -nobrowse -readonly -quiet -mountpoint "$TMP/mnt" "$DMG"
SRC_APP="$TMP/mnt/FreeTube.app"
[[ -d "$SRC_APP" ]] || { echo "FreeTube.app not found in DMG" >&2; exit 1; }

STAGE="$TMP/FreeTube.app"
ditto "$SRC_APP" "$STAGE"
hdiutil detach "$TMP/mnt" -quiet >/dev/null 2>&1 || true

if ! codesign --verify --deep --strict "$STAGE" >/dev/null 2>&1; then
  echo "Downloaded app failed code-signature verification." >&2
  exit 1
fi

mkdir -p "$APP_DIR"
DEST="$APP_DIR/FreeTube.app"
if [[ -d "$DEST" ]]; then
  OLD="$DEST.old-$(date +%s)"
  mv "$DEST" "$OLD"
  if mv "$STAGE" "$DEST"; then
    rm -rf "$OLD"
  else
    mv "$OLD" "$DEST"
    echo "Failed to install; previous version restored." >&2
    exit 1
  fi
else
  mv "$STAGE" "$DEST"
fi

xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
if ! codesign --verify --deep --strict "$DEST" >/dev/null 2>&1; then
  echo "Installed app failed verification." >&2
  exit 1
fi

echo "Installed FreeTube $VER to $DEST"

# Auto-updater (per-user installs only).
if ((SYSTEM_INSTALL)); then
  echo "Note: --system installs are not auto-updated (replacing /Applications needs admin rights)."
else
  SCRIPTS_DEST="$HOME/Library/Scripts"
  mkdir -p "$SCRIPTS_DEST"
  cp "$REPO_DIR/scripts/freetube-autoupdate.sh" "$SCRIPTS_DEST/FreeTubeAutoUpdate.sh"
  chmod +x "$SCRIPTS_DEST/FreeTubeAutoUpdate.sh"

  mkdir -p "$HOME/Library/LaunchAgents"
  sed -e "s|__HOME__|$HOME|g" \
      -e "s|__SCRIPT__|$SCRIPTS_DEST/FreeTubeAutoUpdate.sh|g" \
      "$REPO_DIR/launchd/local.freetube.autoupdate.plist.template" \
      > "$HOME/Library/LaunchAgents/local.freetube.autoupdate.plist"

  UID_NUM="$(id -u)"
  launchctl bootout "gui/$UID_NUM/local.freetube.autoupdate" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_NUM" "$HOME/Library/LaunchAgents/local.freetube.autoupdate.plist"
  launchctl enable "gui/$UID_NUM/local.freetube.autoupdate"
  echo "Auto-updater installed (runs at login and every 6 hours)."
fi

# Restore config snapshot.
if ((RESTORE_CONFIG)); then
  if [[ -z "$CONFIG_DIR" ]]; then
    CONFIG_DIR="$REPO_DIR/../freetube-configs-main"
  fi
  if [[ -x "$CONFIG_DIR/scripts/restore-to-macos.sh" ]]; then
    echo "Restoring config from $CONFIG_DIR…"
    bash "$CONFIG_DIR/scripts/restore-to-macos.sh" --no-launch
  else
    echo "No config snapshot found at $CONFIG_DIR (use --config-dir, or --no-config to skip)." >&2
  fi
fi

if ((MENU_BAR_NOW_PLAYING)); then
  defaults -currentHost write com.apple.controlcenter "NSStatusItem Visible NowPlaying" -bool true
  killall ControlCenter 2>/dev/null || true
  echo "Now Playing menu bar item enabled."
fi

if ((LAUNCH)); then
  open "$DEST"
  echo "FreeTube launched."
fi

echo "Done."

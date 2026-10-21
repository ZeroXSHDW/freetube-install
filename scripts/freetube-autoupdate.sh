#!/bin/bash
# FreeTube auto-updater for macOS.
# Downloads the official GitHub release, verifies its SHA-256 digest, and only
# replaces the app when FreeTube is not running. Rolls back on failure.
# Keeps the last N old versions for rollback safety.
set -uo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
LOG_DIR="$HOME/Library/Logs"
LOG="$LOG_DIR/FreeTubeAutoUpdate.log"
KEEP_OLD=3
FORCE=0
DRY_RUN=0

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }
mkdir -p "$LOG_DIR"

while (($#)); do
  case "$1" in
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --keep) KEEP_OLD="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: freetube-autoupdate.sh [--force] [--dry-run] [--keep N]"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# --- Locate the app -----------------------------------------------------------
APP="${FREETUBE_APP:-}"
if [[ -z "$APP" ]]; then
  for candidate in "$HOME/Applications/FreeTube.app" "/Applications/FreeTube.app"; do
    if [[ -d "$candidate" ]]; then APP="$candidate"; break; fi
  done
fi
if [[ -z "$APP" ]]; then
  log "FreeTube.app not found; nothing to do."
  exit 0
fi

# Refuse to manage a system-wide install without admin rights.
if [[ "$APP" == "/Applications/FreeTube.app" && "$(id -u)" != "0" ]]; then
  log "FreeTube is installed system-wide; auto-update requires admin rights. Skipping."
  exit 0
fi

CURRENT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "0")
ARCH=$(uname -m)
case "$ARCH" in
  arm64) SUFFIX="arm64" ;;
  x86_64) SUFFIX="x64" ;;
  *) log "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# --- Query GitHub for latest release -----------------------------------------
RELEASE_JSON=$(curl -fsSL --retry 3 --connect-timeout 20 \
  -H 'Accept: application/vnd.github+json' \
  "https://api.github.com/repos/FreeTubeApp/FreeTube/releases?per_page=1" 2>/dev/null || true)
if [[ -z "${RELEASE_JSON:-}" ]]; then
  log "Failed to query the GitHub releases API."
  exit 1
fi

PARSED=$(printf '%s' "$RELEASE_JSON" | python3 -c '
import json, sys
try:
    rel = json.load(sys.stdin)[0]
except Exception:
    sys.exit(1)
tag = rel.get("tag_name", "")
ver = tag.lstrip("v").replace("-beta", "")
want = "freetube-%s-beta-mac-%s.dmg" % (ver, sys.argv[1])
for a in rel.get("assets", []):
    if a.get("name") == want:
        digest = (a.get("digest") or "").replace("sha256:", "")
        print("\t".join([tag, ver, want, a.get("browser_download_url", ""), digest]))
        break
' "$SUFFIX")

if [[ -z "${PARSED:-}" ]]; then
  log "No macOS $SUFFIX DMG found in the latest release."
  exit 1
fi

IFS=$'\t' read -r TAG VERSION ASSET_NAME ASSET_URL DIGEST <<< "$PARSED"

if ! python3 - "$CURRENT" "$VERSION" <<'PY'
import sys
def parse(v):
    v = v.strip().lower().lstrip("v").split("-")[0]
    parts = []
    for p in v.split("."):
        try: parts.append(int(p))
        except ValueError: parts.append(0)
    return tuple(parts)
sys.exit(0 if parse(sys.argv[2]) > parse(sys.argv[1]) else 1)
PY
then
  if ((FORCE)); then
    log "Forced reinstall of $VERSION (installed $CURRENT)."
  else
    log "Up to date (installed $CURRENT, latest $VERSION)."
    exit 0
  fi
fi

if ((!FORCE)) && pgrep -f "FreeTube.app/Contents/MacOS/FreeTube" >/dev/null 2>&1; then
  log "Update $VERSION available, but FreeTube is running. Will retry later."
  exit 0
fi

if [[ -z "$DIGEST" ]]; then
  log "Release $TAG has no published SHA-256 digest; refusing to update."
  exit 1
fi

if ((DRY_RUN)); then
  log "[dry-run] Would update FreeTube $CURRENT -> $VERSION ($ASSET_NAME)"
  exit 0
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/freetube-update.XXXXXX") || exit 1
DMG="$TMP/$ASSET_NAME"
MNT="$TMP/mnt"

cleanup() {
  hdiutil detach "$MNT" -quiet >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

log "Downloading FreeTube $VERSION ($ASSET_NAME)…"
if ! curl -fL --retry 3 --connect-timeout 20 -o "$DMG" "$ASSET_URL"; then
  log "Download failed."
  exit 1
fi

ACTUAL=$(shasum -a 256 "$DMG" | awk '{print $1}')
if [[ "$(printf '%s' "$ACTUAL" | tr 'A-F' 'a-f')" != "$(printf '%s' "$DIGEST" | tr 'A-F' 'a-f')" ]]; then
  log "Checksum mismatch! expected $DIGEST, got $ACTUAL. Aborting."
  exit 1
fi
log "Checksum verified: $ACTUAL"

mkdir -p "$MNT"
if ! hdiutil attach -nobrowse -readonly -quiet -mountpoint "$MNT" "$DMG"; then
  log "Could not mount the downloaded DMG."
  exit 1
fi

SRC_APP="$MNT/FreeTube.app"
if [[ ! -d "$SRC_APP" ]]; then
  log "FreeTube.app was not found inside the DMG."
  exit 1
fi

STAGE="$TMP/FreeTube.app"
if ! ditto "$SRC_APP" "$STAGE"; then
  log "Could not copy the app out of the DMG."
  exit 1
fi

if ! codesign --verify --deep --strict "$STAGE" >/dev/null 2>&1; then
  log "The downloaded app failed code-signature verification. Aborting."
  exit 1
fi

hdiutil detach "$MNT" -quiet >/dev/null 2>&1 || true

# --- Rotate old backups (keep last KEEP_OLD) ---------------------------------
OLD_DIR="$HOME/Library/Application Support/FreeTube/.freetube-backups"
mkdir -p "$OLD_DIR"
# Remove backups beyond the keep limit, oldest first.
mapfile -t old_backups < <(ls -1dt "$OLD_DIR"/FreeTube.app.old-* 2>/dev/null || true)
if (( ${#old_backups[@]} >= KEEP_OLD )); then
  for b in "${old_backups[@]:$KEEP_OLD}"; do
    rm -rf "$b" 2>/dev/null || true
  done
fi

OLD="$OLD_DIR/FreeTube.app.old-$(date +%s)"
if ! mv "$APP" "$OLD"; then
  log "Could not move the current app aside. Aborting."
  exit 1
fi

if ! mv "$STAGE" "$APP"; then
  log "Could not install the new app; rolling back."
  mv "$OLD" "$APP" 2>/dev/null || true
  exit 1
fi

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

if ! codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
  log "Installed app failed verification; rolling back."
  rm -rf "$APP"
  mv "$OLD" "$APP" 2>/dev/null || true
  exit 1
fi

rm -rf "$OLD"
NEW=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "$VERSION")
log "Updated FreeTube from $CURRENT to $NEW successfully."

SAFE_VERSION=$(printf '%s' "$NEW" | tr -cd '0-9.')
/usr/bin/osascript -e "display notification \"FreeTube was updated to $SAFE_VERSION. Open it when you're ready.\" with title \"FreeTube updated\"" >/dev/null 2>&1 || true

exit 0
#!/usr/bin/env bash
# Install FreeTube on macOS, verify its SHA-256 digest, restore config, and
# set up the checksum-verified auto-updater, menu bar app, and login helpers.
#
# Designed for per-user installs (no admin rights). Fully idempotent: re-running
# is safe and only downloads/reinstalls when a newer version is available.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="https://api.github.com/repos/FreeTubeApp/FreeTube/releases"
SCRIPTS_DEST="$HOME/Library/Scripts"
LAUNCH_DIR="$HOME/Library/LaunchAgents"
SUPPORT_DIR="$HOME/Library/Application Support/FreeTube"
BAR_DIR="$HOME/Library/Application Support/FreeTubeBar"
LOG_DIR="$HOME/Library/Logs"
APP_DIR="$HOME/Applications"

VERSION="latest"
SYSTEM_INSTALL=0
RESTORE_CONFIG=1
LAUNCH=1
MENU_BAR_NOW_PLAYING=0
SKIP_CHARTS=0
CONFIG_DIR=""
DRY_RUN=0
CHECK_DEPS=0
FORCE_REINSTALL=0
SKIP_MENU_BAR=0

log() { printf '%s  %s\n' "$*" ; }
err() { printf 'ERROR: %s\n' "$*" >&2 ; }

usage() {
  cat <<'USAGE'
Usage: install.sh [options]

Installs the official FreeTube macOS release (SHA-256 verified), sets up the
auto-updater, generates the Top Charts music playlists, installs the native
♫ menu bar app with Now Playing popover, and registers login helpers — all in
one command. Safe to re-run (idempotent).

Options:
  --version VERSION       Pin a version, e.g. 0.25.3 (default: latest)
  --list-versions         Show the last N releases from GitHub and exit
  --system                Install to /Applications (requires sudo; auto-update
                          is then unavailable because replacing needs admin rights)
  --no-config             Skip restoring a config snapshot
  --config-dir DIR        Config snapshot dir (default: ../freetube-configs-main)
  --skip-charts           Do not generate the Top Charts music playlists now
  --menu-bar-now-playing  Enable macOS system Now Playing menu bar item
  --no-launch             Do not open FreeTube when finished
  --dry-run               Print what would happen without changing anything
  --check-deps            Verify required tools are installed (and exit)
  --force                 Reinstall even if already on the latest version
  --skip-menu-bar         Skip building/installing the ♫ menu bar app
  -h, --help              Show this help
USAGE
}

while (($#)); do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --list-versions) LIST_VERSIONS=1; shift ;;
    --system) SYSTEM_INSTALL=1; shift ;;
    --no-config) RESTORE_CONFIG=0; shift ;;
    --config-dir) CONFIG_DIR="$2"; shift 2 ;;
    --skip-charts) SKIP_CHARTS=1; shift ;;
    --menu-bar-now-playing) MENU_BAR_NOW_PLAYING=1; shift ;;
    --no-launch) LAUNCH=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --check-deps) CHECK_DEPS=1; shift ;;
    --force) FORCE_REINSTALL=1; shift ;;
    --skip-menu-bar) SKIP_MENU_BAR=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1"; usage >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  err "This installer targets macOS."
  exit 1
fi

# --- Dependency checks -------------------------------------------------------
REQUIRED_CMDS=(curl python3 hdiutil ditto codesign shasum xattr PlistBuddy)
OPTIONAL_CMDS=(swiftc nowplaying-cli brew)
missing=0
for cmd in "${REQUIRED_CMDS[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Missing required command: $cmd"
    missing=1
  fi
done

if ((CHECK_DEPS)); then
  echo "=== Required commands ==="
  for cmd in "${REQUIRED_CMDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "OK   $cmd  ($(command -v "$cmd"))"
    else
      echo "MISS $cmd"
    fi
  done
  echo "=== Optional commands ==="
  for cmd in "${OPTIONAL_CMDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "OK   $cmd  ($(command -v "$cmd"))"
    else
      echo "MISS $cmd  (optional)"
    fi
  done
  if command -v brew >/dev/null 2>&1; then
    if brew list --formula nowplaying-cli >/dev/null 2>&1; then
      echo "OK   nowplaying-cli (Homebrew formula installed)"
    else
      echo "MISS nowplaying-cli  (install with: brew install nowplaying-cli)"
    fi
  fi
  exit $missing
fi

if ((missing)); then
  err "Install required commands first, or run with --check-deps for details."
  exit 1
fi

if ((SYSTEM_INSTALL)); then
  APP_DIR="/Applications"
fi

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) SUFFIX="arm64" ;;
  x86_64) SUFFIX="x64" ;;
  *) err "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# --- Resolve release ---------------------------------------------------------
resolve_release() {
  local api_url="$1"
  local raw parsed tag ver asset_name asset_url digest
  raw="$(curl -fsSL --retry 3 --connect-timeout 20 -H 'Accept: application/vnd.github+json' "$api_url" 2>/dev/null || true)"
  if [[ -z "$raw" ]]; then return 1; fi
  parsed="$(printf '%s' "$raw" | python3 -c '
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
  if [[ -z "$parsed" ]]; then return 1; fi
  IFS=$'\t' read -r tag ver asset_name asset_url digest <<< "$parsed"
  printf '%s\t%s\t%s\t%s\t%s\n' "$tag" "$ver" "$asset_name" "$asset_url" "$digest"
}

if [[ -n "${LIST_VERSIONS:-}" ]]; then
  raw="$(curl -fsSL --retry 3 --connect-timeout 20 -H 'Accept: application/vnd.github+json' "${API}?per_page=10" 2>/dev/null || true)"
  if [[ -z "$raw" ]]; then err "Could not query GitHub releases API."; exit 1; fi
  printf '%s\n' "$raw" | python3 -c '
import json, sys
try:
    rels = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for r in rels[:10]:
    tag = r.get("tag_name", "unknown")
    print(tag)
'
  exit 0
fi

echo "Resolving FreeTube release…"
if [[ "$VERSION" == "latest" ]]; then
  API_URL="$API?per_page=1"
else
  NORMALIZED="$(printf '%s' "$VERSION" | sed 's/^v//; s/-beta$//')"
  API_URL="$API/tags/v${NORMALIZED}-beta"
fi
RESOLVED="$(resolve_release "$API_URL")" || { err "No macOS $SUFFIX DMG found for the requested release."; exit 1; }
IFS=$'\t' read -r TAG VER ASSET_NAME ASSET_URL DIGEST <<< "$RESOLVED"

if [[ -z "$DIGEST" ]]; then
  err "Release $TAG has no published SHA-256 digest; refusing to install."
  exit 1
fi

# --- Idempotency: skip if already at target version --------------------------
CURRENT_APP=""
for candidate in "$APP_DIR/FreeTube.app" "/Applications/FreeTube.app"; do
  if [[ -d "$candidate" ]]; then CURRENT_APP="$candidate"; break; fi
done
CURRENT_VER=""
if [[ -n "$CURRENT_APP" ]]; then
  CURRENT_VER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CURRENT_APP/Contents/Info.plist" 2>/dev/null || echo "")
fi
if [[ -z "$FORCE_REINSTALL" && -n "$CURRENT_VER" && "$CURRENT_VER" == "$VER" ]]; then
  log "FreeTube $VER is already installed at $CURRENT_APP (skipping download)."
  SKIP_DOWNLOAD=1
else
  SKIP_DOWNLOAD=0
fi

if ((DRY_RUN)); then
  echo "[dry-run] Would install FreeTube $VER ($ASSET_NAME) to $APP_DIR"
  echo "[dry-run] Scripts -> $SCRIPTS_DEST"
  echo "[dry-run] LaunchAgents -> $LAUNCH_DIR"
  echo "[dry-run] Config restore: $RESTORE_CONFIG (from $CONFIG_DIR)"
  echo "[dry-run] Launch at end: $LAUNCH"
  exit 0
fi

# --- Download & verify -------------------------------------------------------
if ((!SKIP_DOWNLOAD)); then
  if pgrep -f "FreeTube.app/Contents/MacOS/FreeTube" >/dev/null 2>&1; then
    log "Quitting running FreeTube…"
    osascript -e 'tell application "FreeTube" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do
      pgrep -f "FreeTube.app/Contents/MacOS/FreeTube" >/dev/null 2>&1 || break
      sleep 0.5
    done
  fi

  TMP="$(mktemp -d "${TMPDIR:-/tmp}/freetube-install.XXXXXX")"
  trap 'rm -rf "$TMP"' EXIT
  DMG="$TMP/$ASSET_NAME"

  log "Downloading $ASSET_NAME…"
  curl -fL --retry 3 --connect-timeout 20 -o "$DMG" "$ASSET_URL"

  ACTUAL="$(shasum -a 256 "$DMG" | awk '{print $1}')"
  if [[ "$(printf '%s' "$ACTUAL" | tr 'A-F' 'a-f')" != "$(printf '%s' "$DIGEST" | tr 'A-F' 'a-f')" ]]; then
    err "Checksum mismatch! expected $DIGEST, got $ACTUAL"
    exit 1
  fi
  log "Checksum verified: $ACTUAL"

  mkdir -p "$TMP/mnt"
  hdiutil attach -nobrowse -readonly -quiet -mountpoint "$TMP/mnt" "$DMG"
  SRC_APP="$TMP/mnt/FreeTube.app"
  [[ -d "$SRC_APP" ]] || { err "FreeTube.app not found in DMG"; exit 1; }

  STAGE="$TMP/FreeTube.app"
  ditto "$SRC_APP" "$STAGE"
  hdiutil detach "$TMP/mnt" -quiet >/dev/null 2>&1 || true

  if ! codesign --verify --deep --strict "$STAGE" >/dev/null 2>&1; then
    err "Downloaded app failed code-signature verification."
    exit 1
  fi
fi

mkdir -p "$APP_DIR"
DEST="$APP_DIR/FreeTube.app"
if [[ -d "$DEST" ]]; then
  OLD="$DEST.old-$(date +%s)"
  mv "$DEST" "$OLD"
  if [[ -n "${SKIP_DOWNLOAD:-}" && "$SKIP_DOWNLOAD" == "1" ]]; then
    # Idempotent path: nothing to replace; restore and move on.
    mv "$OLD" "$DEST"
  else
    if mv "$STAGE" "$DEST"; then
      rm -rf "$OLD"
    else
      mv "$OLD" "$DEST"
      err "Failed to install; previous version restored."
      exit 1
    fi
  fi
else
  if [[ -n "${SKIP_DOWNLOAD:-}" && "$SKIP_DOWNLOAD" == "1" ]]; then
    err "No app found to keep in place; something is inconsistent."
    exit 1
  fi
  mv "$STAGE" "$DEST"
fi

xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
if ! codesign --verify --deep --strict "$DEST" >/dev/null 2>&1; then
  err "Installed app failed verification."
  exit 1
fi

log "Installed FreeTube $VER to $DEST"

# --- Auto-updater (per-user installs only) -----------------------------------
if ((SYSTEM_INSTALL)); then
  log "Note: --system installs are not auto-updated (replacing /Applications needs admin rights)."
else
  mkdir -p "$SCRIPTS_DEST" "$LAUNCH_DIR"
  cp "$REPO_DIR/scripts/freetube-autoupdate.sh" "$SCRIPTS_DEST/FreeTubeAutoUpdate.sh"
  chmod +x "$SCRIPTS_DEST/FreeTubeAutoUpdate.sh"

  sed -e "s|__HOME__|$HOME|g" \
      -e "s|__SCRIPT__|$SCRIPTS_DEST/FreeTubeAutoUpdate.sh|g" \
      "$REPO_DIR/launchd/local.freetube.autoupdate.plist.template" \
      > "$LAUNCH_DIR/local.freetube.autoupdate.plist"

  UID_NUM="$(id -u)"
  launchctl bootout "gui/$UID_NUM/local.freetube.autoupdate" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_NUM" "$LAUNCH_DIR/local.freetube.autoupdate.plist" 2>/dev/null || true
  launchctl enable "gui/$UID_NUM/local.freetube.autoupdate" 2>/dev/null || true
  log "Auto-updater installed (runs at login + every 6 h)."
fi

# --- Helper scripts ----------------------------------------------------------
mkdir -p "$SCRIPTS_DEST"
for script in update-top-music.py update-top-music.sh play-genre.sh resume-last.sh \
              play-favorites.sh play-watch-later.sh audio-pause.sh freetube-doctor.sh \
              freetube-status.sh freetube-backup.sh freetube-cleanup.sh; do
  cp "$REPO_DIR/scripts/$script" "$SCRIPTS_DEST/$script"
done
chmod +x "$SCRIPTS_DEST/update-top-music.sh" "$SCRIPTS_DEST/play-genre.sh" \
  "$SCRIPTS_DEST/resume-last.sh" "$SCRIPTS_DEST/play-favorites.sh" \
  "$SCRIPTS_DEST/play-watch-later.sh" "$SCRIPTS_DEST/audio-pause.sh" \
  "$SCRIPTS_DEST/freetube-doctor.sh" "$SCRIPTS_DEST/freetube-status.sh" \
  "$SCRIPTS_DEST/freetube-backup.sh" "$SCRIPTS_DEST/freetube-cleanup.sh"

# Top Charts LaunchAgent
sed -e "s|__HOME__|$HOME|g" \
    -e "s|__SCRIPT__|$SCRIPTS_DEST/update-top-music.sh|g" \
    "$REPO_DIR/launchd/local.freetube.topmusic.plist.template" \
    > "$LAUNCH_DIR/local.freetube.topmusic.plist"
UID_NUM="$(id -u)"
launchctl bootout "gui/$UID_NUM/local.freetube.topmusic" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$LAUNCH_DIR/local.freetube.topmusic.plist" 2>/dev/null || true
launchctl enable "gui/$UID_NUM/local.freetube.topmusic" 2>/dev/null || true
log "Top Charts updater installed."

# Resume-on-login LaunchAgent
sed -e "s|__HOME__|$HOME|g" \
    -e "s|__SCRIPT__|$SCRIPTS_DEST/resume-last.sh|g" \
    "$REPO_DIR/launchd/local.freetube.resume.plist.template" \
    > "$LAUNCH_DIR/local.freetube.resume.plist"
launchctl bootout "gui/$UID_NUM/local.freetube.resume" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$LAUNCH_DIR/local.freetube.resume.plist" 2>/dev/null || true
launchctl enable "gui/$UID_NUM/local.freetube.resume" 2>/dev/null || true
log "Resume-on-login helper installed."

# --- Menu bar app (FreeTubeBar) ----------------------------------------------
if ((!SKIP_MENU_BAR)); then
  mkdir -p "$BAR_DIR"
  if command -v swiftc >/dev/null 2>&1; then
    swiftc -parse-as-library -swift-version 5 -O \
      "$REPO_DIR/bar/FreeTubeBar.swift" -o "$BAR_DIR/FreeTubeBar"
    sed -e "s|__HOME__|$HOME|g" \
        -e "s|__BIN__|$BAR_DIR/FreeTubeBar|g" \
        "$REPO_DIR/launchd/local.freetube.bar.plist.template" \
        > "$LAUNCH_DIR/local.freetube.bar.plist"
    launchctl bootout "gui/$UID_NUM/local.freetube.bar" 2>/dev/null || true
    launchctl bootstrap "gui/$UID_NUM" "$LAUNCH_DIR/local.freetube.bar.plist" 2>/dev/null || true
    launchctl enable "gui/$UID_NUM/local.freetube.bar" 2>/dev/null || true
    log "FreeTubeBar menu bar app installed (♫ icon)."

    swiftc -O "$REPO_DIR/bar/audiodevice.swift" -o "$BAR_DIR/audiodevice"
    sed -e "s|__HOME__|$HOME|g" \
        -e "s|__SCRIPT__|$SCRIPTS_DEST/audio-pause.sh|g" \
        "$REPO_DIR/launchd/local.freetube.audiopause.plist.template" \
        > "$LAUNCH_DIR/local.freetube.audiopause.plist"
    launchctl bootout "gui/$UID_NUM/local.freetube.audiopause" 2>/dev/null || true
    launchctl bootstrap "gui/$UID_NUM" "$LAUNCH_DIR/local.freetube.audiopause.plist" 2>/dev/null || true
    launchctl enable "gui/$UID_NUM/local.freetube.audiopause" 2>/dev/null || true
    log "AirPods auto-pause watcher installed."
  else
    log "Note: swiftc not found; skipping menu bar app (install Xcode CLT: xcode-select --install)."
  fi
else
  log "Skipping menu bar app (--skip-menu-bar)."
fi

# --- nowplaying-cli recommendation ------------------------------------------
if ! command -v nowplaying-cli >/dev/null 2>&1; then
  log "Tip: install nowplaying-cli for reliable media controls: brew install nowplaying-cli"
fi

# --- Config snapshot restore -------------------------------------------------
if ((RESTORE_CONFIG)); then
  if [[ -z "$CONFIG_DIR" ]]; then
    CONFIG_DIR="$REPO_DIR/../freetube-configs-main"
  fi
  if [[ -x "$CONFIG_DIR/scripts/restore-to-macos.sh" ]]; then
    log "Restoring config from $CONFIG_DIR…"
    bash "$CONFIG_DIR/scripts/restore-to-macos.sh" --no-launch
  else
    log "No config snapshot at $CONFIG_DIR (use --config-dir or --no-config to skip)."
  fi
fi

# --- Default settings for fresh installs -------------------------------------
mkdir -p "$SUPPORT_DIR"
if [[ ! -s "$SUPPORT_DIR/settings.db" ]]; then
  log "Writing default playback settings…"
  python3 - "$SUPPORT_DIR/settings.db" <<'PY'
import json, sys
settings = {
    "backendPreference": "local",
    "backendFallback": True,
    "useRssFeeds": True,
    "autoplayPlaylists": True,
    "autoplayVideos": True,
    "playNextVideo": True,
    "defaultVideoFormat": "dash",
    "defaultQuality": "720",
    "defaultInterval": 0,
    "defaultAutoplayInterruptionIntervalHours": 12,
    "landingPage": "userPlaylists",
    "expandSideBar": True,
    "checkForUpdates": True,
    "defaultProfile": "allChannels",
    "rememberHistory": True,
    "userPlaylistsSortBy": "latest_played_first",
}
with open(sys.argv[1], "w", encoding="utf-8") as f:
    for k, v in settings.items():
        f.write(json.dumps({"_id": k, "value": v}, separators=(",", ":")) + "\n")
PY
fi

# --- Generate Top Charts now -------------------------------------------------
if ((!SKIP_CHARTS)); then
  if pgrep -f "FreeTube.app/Contents/MacOS/FreeTube" >/dev/null 2>&1; then
    log "FreeTube is running; skipping Top Charts generation (refreshes on schedule)."
  elif [[ -x "$SCRIPTS_DEST/update-top-music.sh" ]]; then
    [[ -f "$SUPPORT_DIR/playlists.db" ]] || : > "$SUPPORT_DIR/playlists.db"
    log "Generating Top Charts music playlists (may take a minute)…"
    "$SCRIPTS_DEST/update-top-music.sh" || log "Top Charts generation failed (will retry on schedule)."
  fi
fi

if ((MENU_BAR_NOW_PLAYING)); then
  defaults -currentHost write com.apple.controlcenter "NSStatusItem Visible NowPlaying" -bool true 2>/dev/null || true
  killall ControlCenter 2>/dev/null || true
  log "macOS Now Playing menu bar item enabled."
fi

if ((LAUNCH)); then
  open "$DEST"
  log "FreeTube launched."
fi

log "Done."
#!/usr/bin/env bash
# Uninstall FreeTube and/or its auto-updater. User data is kept by default.
set -euo pipefail

SYSTEM=0
PURGE=0
ASSUME_YES=0

usage() {
  cat <<'USAGE'
Usage: uninstall.sh [options]

Removes FreeTube.app and the auto-updater. Your profile, playlists and history
are left in place unless --purge is given.

Options:
  --system    Also remove /Applications/FreeTube.app
  --purge     Move ~/Library/Application Support/FreeTube aside (not deleted)
  -y, --yes   Do not prompt
  -h, --help  Show this help
USAGE
}

while (($#)); do
  case "$1" in
    --system) SYSTEM=1 ;;
    --purge) PURGE=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if ((!ASSUME_YES)); then
  read -r -p "Uninstall FreeTube? [y/N] " answer
  [[ "$answer" =~ ^[Yy] ]] || { echo "Aborted."; exit 0; }
fi

# Unload the updaters.
UID_NUM="$(id -u)"
launchctl bootout "gui/$UID_NUM/local.freetube.autoupdate" 2>/dev/null || true
launchctl bootout "gui/$UID_NUM/local.freetube.topmusic" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/local.freetube.autoupdate.plist"
rm -f "$HOME/Library/LaunchAgents/local.freetube.topmusic.plist"
rm -f "$HOME/Library/Scripts/FreeTubeAutoUpdate.sh"
rm -f "$HOME/Library/Scripts/update-top-music.py"
rm -f "$HOME/Library/Scripts/update-top-music.sh"
echo "Auto-updater and Top Charts updater removed."

# Remove the app.
for candidate in "$HOME/Applications/FreeTube.app" "/Applications/FreeTube.app"; do
  if [[ -d "$candidate" ]]; then
    if [[ "$candidate" == "/Applications/FreeTube.app" && "$SYSTEM" != "1" ]]; then
      echo "Skipping system app $candidate (use --system to remove it)."
      continue
    fi
    rm -rf "$candidate"
    echo "Removed $candidate"
  fi
done

# Optionally move data aside.
if ((PURGE)); then
  DATA="$HOME/Library/Application Support/FreeTube"
  if [[ -d "$DATA" ]]; then
    DEST="$DATA.removed-$(date +%Y%m%d-%H%M%S)"
    mv "$DATA" "$DEST"
    echo "Moved user data to $DEST (delete it manually when you are sure)."
  fi
fi

echo "Uninstall complete."

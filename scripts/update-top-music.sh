#!/usr/bin/env bash
# Update FreeTube's auto-generated "Top Charts" playlists.
#
# Scheduled runs (no flags): update only when FreeTube is closed.
# Manual refresh:            --force quits FreeTube, updates, relaunches.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$DIR/update-top-music.py"
LOG="$HOME/Library/Logs/FreeTubeTopMusic.log"
mkdir -p "$HOME/Library/Logs"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

FORCE=0
DRY=0
while (($#)); do
  case "$1" in
    --force) FORCE=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help)
      echo "Usage: update-top-music.sh [--force] [--dry-run]" >&2
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if ! command -v python3 >/dev/null 2>&1; then
  log "python3 not found; aborting."
  exit 1
fi

if [[ ! -f "$PY" ]]; then
  log "missing $PY; aborting."
  exit 1
fi

WAS_RUNNING=0
if pgrep -f "FreeTube.app/Contents/MacOS/FreeTube" >/dev/null 2>&1; then
  WAS_RUNNING=1
  if ((FORCE)); then
    log "Quitting FreeTube to refresh Top Charts…"
    osascript -e 'tell application "FreeTube" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
      pgrep -f "FreeTube.app/Contents/MacOS/FreeTube" >/dev/null 2>&1 || break
      sleep 0.5
    done
    if pgrep -f "FreeTube.app/Contents/MacOS/FreeTube" >/dev/null 2>&1; then
      log "FreeTube is still running; aborting."
      exit 1
    fi
  else
    log "FreeTube is running; skipping (run with --force to refresh now)."
    exit 0
  fi
fi

DB="$HOME/Library/Application Support/FreeTube/playlists.db"
if [[ ! -f "$DB" ]]; then
  log "Missing $DB; start FreeTube once first."
  exit 1
fi

if ((DRY)); then
  python3 "$PY" "$DB" --dry-run | tee -a "$LOG"
else
  python3 "$PY" "$DB" | tee -a "$LOG"
fi
log "Top Charts refresh finished."

if ((WAS_RUNNING)) && ((FORCE)); then
  for candidate in "$HOME/Applications/FreeTube.app" "/Applications/FreeTube.app"; do
    if [[ -d "$candidate" ]]; then open "$candidate"; break; fi
  done
  log "FreeTube relaunched."
fi

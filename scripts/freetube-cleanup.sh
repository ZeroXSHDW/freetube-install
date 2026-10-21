#!/usr/bin/env bash
# freetube-cleanup — rotate old logs, remove stale DMGs and temp files,
# and prune old app backups.
set -uo pipefail

DRY=0
KEEP_LOGS=10
KEEP_BACKUPS=5

while (($#)); do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --keep-logs) KEEP_LOGS="$2"; shift 2 ;;
    --keep-backups) KEEP_BACKUPS="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: freetube-cleanup.sh [--dry-run] [--keep-logs N] [--keep-backups N]"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

LOG_DIR="$HOME/Library/Logs"
BACKUP_DIR="$HOME/Library/Application Support/FreeTube/.freetube-backups"
TMP_PATTERN="/tmp/freetube-install.* /tmp/freetube-update.*"
DO=()  # actions to take

log() { if ((DRY)); then echo "[dry-run] $*"; else echo "$*"; fi }

# --- Rotate logs ---
for log in FreeTubeAutoUpdate.log FreeTubeTopMusic.log FreeTubeAirPods.log FreeTubeBar.log; do
  path="$LOG_DIR/$log"
  if [[ -f "$path" ]]; then
    size=$(wc -c <"$path" 2>/dev/null || echo 0)
    if ((size > 5_000_000)); then  # >5 MB
      if ((DRY)); then
        log "Would rotate $log ($size bytes)"
      else
        mv "$path" "$path.$(date +%Y%m%d-%H%M%S)"
        touch "$path"
        log "Rotated $log"
      fi
    fi
  fi
done

# --- Remove old rolled logs ---
mapfile -t old_logs < <(find "$LOG_DIR" -maxdepth 1 -name 'FreeTube*.log.*' -mtime +7 2>/dev/null || true)
for old in "${old_logs[@]}"; do
  if ((DRY)); then log "Would remove old log $old"; else rm -f "$old"; log "Removed old log $old"; fi
done

# --- Clean temp DMGs ---
mapfile -t tmp_dirs < <(find /tmp -maxdepth 1 -name 'freetube-install.*' -o -name 'freetube-update.*' 2>/dev/null || true)
for d in "${tmp_dirs[@]}"; do
  if ((DRY)); then log "Would remove temp dir $d"; else rm -rf "$d"; log "Removed temp dir $d"; fi
done

# --- Prune old app backups ---
if [[ -d "$BACKUP_DIR" ]]; then
  mapfile -t old_backups < <(ls -1dt "$BACKUP_DIR"/FreeTube.app.old-* 2>/dev/null || true)
  if (( ${#old_backups[@]} > KEEP_BACKUPS )); then
    for b in "${old_backups[@]:$KEEP_BACKUPS}"; do
      if ((DRY)); then log "Would remove old backup $b"; else rm -rf "$b"; log "Removed old backup $b"; fi
    done
  fi
fi

log "Cleanup complete."
#!/usr/bin/env bash
# freetube-cleanup — rotate large logs, remove stale temp DMGs, prune old backups.
set -uo pipefail

DRY=0
KEEP_LOGS=7      # days to keep rolled logs
KEEP_BACKUPS=5

while (($#)); do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --keep-logs) KEEP_LOGS="$2"; shift 2 ;;
    --keep-backups) KEEP_BACKUPS="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: freetube-cleanup.sh [--dry-run] [--keep-logs DAYS] [--keep-backups N]"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

LOG_DIR="$HOME/Library/Logs"
BACKUP_DIR="$HOME/Library/Application Support/FreeTube/.freetube-backups"

log() { if ((DRY)); then echo "[dry-run] $*"; else echo "$*"; fi }

rm_file() {
  if ((DRY)); then log "Would remove $1"; else rm -f "$1"; log "Removed $1"; fi
}

# --- Rotate large logs (> 5 MB) ---
for log in FreeTubeAutoUpdate.log FreeTubeTopMusic.log FreeTubeAirPods.log \
           FreeTubeBar.log FreeTubeInstaller.log; do
  path="$LOG_DIR/$log"
  if [[ -f "$path" ]]; then
    size=$(wc -c <"$path" 2>/dev/null || echo 0)
    if ((size > 5000000)); then
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

# --- Remove rolled logs older than KEEP_LOGS days ---
while IFS= read -r old; do
  [[ -n "$old" ]] && rm_file "$old"
done < <(find "$LOG_DIR" -maxdepth 1 -name 'FreeTube*.log.*' -type f -mtime +"$KEEP_LOGS" 2>/dev/null)

# --- Clean temp DMG dirs ---
while IFS= read -r d; do
  [[ -n "$d" ]] || continue
  if ((DRY)); then log "Would remove temp dir $d"; else rm -rf "$d"; log "Removed temp dir $d"; fi
done < <(find /tmp -maxdepth 1 \( -name 'freetube-install.*' -o -name 'freetube-update.*' \) 2>/dev/null)

# --- Prune old app backups ---
if [[ -d "$BACKUP_DIR" ]]; then
  keep=$KEEP_BACKUPS
  while IFS= read -r b; do
    [[ -n "$b" ]] || continue
    if ((keep > 0)); then keep=$((keep - 1)); continue; fi
    if ((DRY)); then log "Would remove old backup $b"; else rm -rf "$b"; log "Removed old backup $b"; fi
  done < <(ls -1dt "$BACKUP_DIR"/FreeTube.app.old-* 2>/dev/null)
fi

log "Cleanup complete."

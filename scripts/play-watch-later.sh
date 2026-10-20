#!/usr/bin/env bash
# Flush the bar app's watchLater.json into FreeTube's built-in "Watch Later"
# playlist and start playing it. Quits FreeTube first so the database write
# is not overwritten.
set -euo pipefail

SCRIPTS="$HOME/Library/Scripts"
DB="$HOME/Library/Application Support/FreeTube/playlists.db"
WL="$HOME/Library/Application Support/FreeTube/watchLater.json"

[[ -f "$WL" ]] || { echo "No watch-later list yet." >&2; exit 1; }

if pgrep -f "FreeTube.app/Contents/MacOS/FreeTube" >/dev/null 2>&1; then
  osascript -e 'tell application "FreeTube" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    pgrep -f "FreeTube.app/Contents/MacOS/FreeTube" >/dev/null 2>&1 || break
    sleep 0.5
  done
fi

python3 "$SCRIPTS/update-top-music.py" "$DB" --watch-later-only

FIRST=$(python3 - "$WL" <<'PY'
import json, pathlib, sys
items = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print(items[0]["videoId"] if items else "")
PY
)

if [[ -z "$FIRST" ]]; then
  echo "No watch-later items." >&2
  exit 1
fi

open -a FreeTube "https://www.youtube.com/watch?v=$FIRST&list=watchLater"
echo "Playing watch-later list."

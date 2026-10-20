#!/usr/bin/env bash
# Flush the bar app's favorites.json into FreeTube's built-in "Favorites"
# playlist and start playing it. Quits FreeTube first so the database write
# is not overwritten.
set -euo pipefail

SCRIPTS="$HOME/Library/Scripts"
DB="$HOME/Library/Application Support/FreeTube/playlists.db"
FAV="$HOME/Library/Application Support/FreeTube/favorites.json"

[[ -f "$FAV" ]] || { echo "No favorites yet." >&2; exit 1; }

# Quit FreeTube so our playlists.db write survives.
if pgrep -f "FreeTube.app/Contents/MacOS/FreeTube" >/dev/null 2>&1; then
  osascript -e 'tell application "FreeTube" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    pgrep -f "FreeTube.app/Contents/MacOS/FreeTube" >/dev/null 2>&1 || break
    sleep 0.5
  done
fi

python3 "$SCRIPTS/update-top-music.py" "$DB" --favorites-only

FIRST=$(python3 - "$FAV" <<'PY'
import json, pathlib, sys
favs = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print(favs[0]["videoId"] if favs else "")
PY
)

if [[ -z "$FIRST" ]]; then
  echo "No favorites." >&2
  exit 1
fi

open -a FreeTube "https://www.youtube.com/watch?v=$FIRST&list=favorites"
echo "Playing favorites."

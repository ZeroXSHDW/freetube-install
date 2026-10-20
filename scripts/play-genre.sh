#!/usr/bin/env bash
# Play a genre's Top Charts playlist in FreeTube by deep-linking to its first video.
# Usage: play-genre.sh <genre-name-or-playlist-id>
set -euo pipefail

if (($# != 1)); then
  echo "Usage: play-genre.sh <genre-name-or-playlist-id>" >&2
  exit 2
fi

ARG="$1"
MANIFEST="$HOME/Library/Application Support/FreeTube/top-charts.json"

if [[ ! -f "$MANIFEST" ]]; then
  echo "No Top Charts manifest at $MANIFEST. Run the updater first." >&2
  exit 1
fi

read -r PID FIRST <<< "$(python3 - "$MANIFEST" "$ARG" <<'PY'
import json, pathlib, sys
manifest = pathlib.Path(sys.argv[1])
arg = sys.argv[2].strip().lower()
data = json.loads(manifest.read_text(encoding="utf-8"))
for entry in data:
    if arg in (entry.get("name", "").lower(), entry.get("playlistId", "").lower()):
        print(entry["playlistId"], entry["firstVideoId"])
        sys.exit(0)
print("", "")
sys.exit(1)
PY
)"

if [[ -z "$PID" || -z "$FIRST" ]]; then
  echo "No Top Charts playlist matches '$ARG'." >&2
  echo "Available genres:" >&2
  python3 -c "import json,pathlib; [print('  ', e['name']) for e in json.loads(pathlib.Path('$MANIFEST').read_text())]" >&2
  exit 1
fi

URL="https://www.youtube.com/watch?v=$FIRST&list=$PID"
echo "Playing $ARG -> $URL"

# Remember this as the last-played genre so "resume on login" can pick it up.
python3 - "$MANIFEST" "$PID" "$FIRST" <<'PY'
import json, pathlib, sys
manifest = pathlib.Path(sys.argv[1])
pid, first = sys.argv[2], sys.argv[3]
data = json.loads(manifest.read_text(encoding="utf-8"))
name = pid
for entry in data:
    if entry.get("playlistId") == pid:
        name = entry.get("name", pid)
        break
state = pathlib.Path.home() / "Library/Application Support/FreeTube/last-genre.json"
state.write_text(json.dumps({"name": name, "playlistId": pid, "videoId": first}, ensure_ascii=False), encoding="utf-8")
PY

open -a FreeTube "$URL"

#!/usr/bin/env bash
# Play a FreeTube Top Charts genre playlist.
#
# Usage: play-genre.sh <genre-name> [options]
#   --list              List all available genres and exit
#   --random            Play a random video from the genre's playlist
#   --shuffle           Shuffle-play (pick random video + random genre)
#   --resume            Resume the last-played genre/video
#   --notify            Show a macOS notification when playback starts
#   --dry-run           Print the URL without opening it
set -euo pipefail

ARG=""
LIST=0
RANDOM_VID=0
SHUFFLE_ALL=0
RESUME=0
NOTIFY=0
DRY_RUN=0

while (($#)); do
  case "$1" in
    --list) LIST=1; shift ;;
    --random) RANDOM_VID=1; shift ;;
    --shuffle) SHUFFLE_ALL=1; shift ;;
    --resume) RESUME=1; shift ;;
    --notify) NOTIFY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      echo "Usage: play-genre.sh <genre> [--random|--shuffle|--resume|--notify|--dry-run|--list]"; exit 0 ;;
    *) ARG="$1"; shift ;;
  esac
done

MANIFEST="$HOME/Library/Application Support/FreeTube/top-charts.json"

if [[ ! -f "$MANIFEST" ]]; then
  echo "No Top Charts manifest at $MANIFEST. Run update-top-music.sh first." >&2
  exit 1
fi

# --- List genres --------------------------------------------------------------
if ((LIST)); then
  python3 - "$MANIFEST" <<'PY'
import json, pathlib
data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print("Available Top Charts genres:")
for entry in data:
    print(f"  - {entry['name']}  ({entry['playlistId']})")
print(f"  Total: {len(data)} genres")
PY
  exit 0
fi

# --- Resolve playlist + first video ------------------------------------------
read -r PID FIRST NAME <<< "$(python3 - "$MANIFEST" "$ARG" "$RESUME" "$SHUFFLE_ALL" "$RANDOM_VID" <<'PY'
import json, pathlib, sys, random
manifest = pathlib.Path(sys.argv[1])
arg = sys.argv[2].strip().lower()
resume = sys.argv[3] == "1"
shuffle_all = sys.argv[4] == "1"
data = json.loads(manifest.read_text(encoding="utf-8"))

if resume:
    state_path = pathlib.Path.home() / "Library/Application Support/FreeTube/last-genre.json"
    if state_path.is_file():
        try:
            st = json.loads(state_path.read_text(encoding="utf-8"))
            print(st["playlistId"], st["videoId"], st.get("name", ""), "resume")
            sys.exit(0)
        except Exception:
            pass

if shuffle_all:
    entry = random.choice(data)
    vid = random.choice(entry.get("videoIds", [entry["firstVideoId"]]))
    print(entry["playlistId"], vid, entry["name"], "shuffle")
    sys.exit(0)

for entry in data:
    if arg in (entry.get("name", "").lower(), entry.get("playlistId", "").lower()):
        if sys.argv[5] == "1":  # --random
            vid = random.choice(entry.get("videoIds", [entry["firstVideoId"]]))
        else:
            vid = entry["firstVideoId"]
        print(entry["playlistId"], vid, entry["name"], "play")
        sys.exit(0)
print("", "", "", "")
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
if ((DRY_RUN)); then
  echo "Would play: $NAME -> $URL"
  exit 0
fi

echo "Playing $NAME -> $URL"

# Remember as last-played genre for resume-on-login.
python3 - "$MANIFEST" "$PID" "$FIRST" "$NAME" <<'PY'
import json, pathlib, sys
manifest = pathlib.Path(sys.argv[1])
pid, first, name = sys.argv[2], sys.argv[3], sys.argv[4]
data = json.loads(manifest.read_text(encoding="utf-8"))
for entry in data:
    if entry.get("playlistId") == pid:
        name = entry.get("name", pid)
        break
state = pathlib.Path.home() / "Library/Application Support/FreeTube/last-genre.json"
state.write_text(json.dumps({"name": name, "playlistId": pid, "videoId": first}, ensure_ascii=False), encoding="utf-8")
PY

if ((NOTIFY)); then
  /usr/bin/osascript -e "display notification \"$NAME\" with title \"FreeTube — Now Playing\"" >/dev/null 2>&1 || true
fi

open -a FreeTube "$URL"
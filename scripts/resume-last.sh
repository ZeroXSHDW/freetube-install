#!/usr/bin/env bash
# Resume the last played genre on login, if enabled.
set -uo pipefail

STATE="$HOME/Library/Application Support/FreeTube/last-genre.json"
FLAG="$HOME/Library/Application Support/FreeTube/resume-on-login"

[[ -f "$FLAG" ]] || exit 0
[[ -f "$STATE" ]] || exit 0

read -r PID VIDEO <<< "$(python3 - "$STATE" <<'PY'
import json, pathlib, sys
try:
    d = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    print(d.get("playlistId", ""), d.get("videoId", ""))
except Exception:
    print("", "")
PY
)"

[[ -n "$PID" && -n "$VIDEO" ]] || exit 0

sleep 3
open -a FreeTube "https://www.youtube.com/watch?v=$VIDEO&list=$PID"

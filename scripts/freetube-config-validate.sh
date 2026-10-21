#!/usr/bin/env bash
# freetube-config-validate — validate FreeTube config files (settings.db,
# playlists.db, favorites.json, watchLater.json, top-charts.json).
#
# Usage: freetube-config-validate.sh [--fix] [--dir DIR]
set -uo pipefail

SUPPORT_DIR="$HOME/Library/Application Support/FreeTube"
FIX=0

while (($#)); do
  case "$1" in
    --fix) FIX=1; shift ;;
    --dir) SUPPORT_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: freetube-config-validate.sh [--fix] [--dir DIR]"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

FAIL=0
WARN=0

pass() { printf '  ✅ %s\n' "$*"; }
fail() { printf '  ❌ %s\n' "$*"; FAIL=1; }
warn() { printf '  ⚠️  %s\n' "$*"; WARN=1; }
fix() { printf '  🔧 %s\n' "$*"; }

echo "Validating FreeTube config in $SUPPORT_DIR"
echo "=========================================="
echo

# --- settings.db ---
if [[ ! -f "$SUPPORT_DIR/settings.db" ]]; then
  fail "settings.db not found"
else
  python3 - "$SUPPORT_DIR/settings.db" "$FIX" <<'PY'
import json, pathlib, sys, os

path = pathlib.Path(sys.argv[1])
fix = sys.argv[2] == "1"

required = {
    "backendPreference": ("local", str),
    "backendFallback": (True, bool),
    "useRssFeeds": (True, bool),
    "autoplayPlaylists": (True, bool),
    "autoplayVideos": (True, bool),
    "playNextVideo": (True, bool),
    "defaultVideoFormat": ("dash", str),
    "defaultQuality": ("720", str),
    "defaultAutoplayInterruptionIntervalHours": (12, int),
    "landingPage": ("userPlaylists", str),
    "checkForUpdates": (True, bool),
    "defaultProfile": ("allChannels", str),
    "rememberHistory": (True, bool),
}

settings = {}
lines = path.read_text(encoding="utf-8").splitlines()
for i, line in enumerate(lines):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
        settings[d.get("_id")] = d.get("value")
    except json.JSONDecodeError as e:
        print(f"  ❌ settings.db line {i+1}: invalid JSON ({e})")
        sys.exit(1)

changed = False
for key, (expected, typ) in required.items():
    val = settings.get(key)
    if val is None:
        print(f"  ❌ settings.db: missing key '{key}' (expected {expected!r})")
        if fix:
            settings[key] = expected
            changed = True
            print(f"     🔧 Added '{key}' = {expected!r}")
    elif not isinstance(val, typ):
        print(f"  ❌ settings.db: '{key}' is {type(val).__name__}, expected {typ.__name__} ({expected!r})")
        if fix:
            settings[key] = expected
            changed = True
            print(f"     🔧 Fixed '{key}' = {expected!r}")
    else:
        print(f"  ✅ settings.db: {key} = {val!r}")

if fix and changed:
    with open(path, "w", encoding="utf-8") as f:
        for k, v in settings.items():
            f.write(json.dumps({"_id": k, "value": v}, separators=(",", ":")) + "\n")
    print("  🔧 settings.db: wrote fixes")
PY
fi

echo

# --- playlists.db ---
if [[ ! -f "$SUPPORT_DIR/playlists.db" ]]; then
  fail "playlists.db not found"
else
  python3 - "$SUPPORT_DIR/playlists.db" <<'PY'
import json, pathlib, sys

path = pathlib.Path(sys.argv[1])
docs, order = {}, []
for line in path.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except json.JSONDecodeError as e:
        print(f"  ❌ playlists.db: invalid JSON line ({e})")
        sys.exit(1)
    i = d.get("_id")
    if d.get("$$deleted"):
        if i in docs:
            del docs[i]; order.remove(i)
        continue
    if i not in order:
        order.append(i)
    docs[i] = d

print(f"  ✅ playlists.db: {len(order)} playlists")
for pid in order:
    d = docs[pid]
    name = d.get("playlistName", pid)
    videos = [v for v in d.get("videos", []) if v.get("videoId")]
    has_name = bool(d.get("playlistName"))
    has_desc = bool(d.get("description"))
    status = "✅" if has_name and has_desc else "⚠️ "
    print(f"     {status} {name} ({pid}) — {len(videos)} tracks")
PY
fi

echo

# --- favorites.json ---
if [[ ! -f "$SUPPORT_DIR/favorites.json" ]]; then
  warn "favorites.json not found (run play-genre.sh or menu bar to create)"
else
  python3 - "$SUPPORT_DIR/favorites.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, list):
        print(f"  ✅ favorites.json: {len(data)} pinned tracks")
    else:
        print("  ❌ favorites.json: not a JSON array")
        sys.exit(1)
except json.JSONDecodeError as e:
    print(f"  ❌ favorites.json: invalid JSON ({e})")
    sys.exit(1)
PY
fi

# --- watchLater.json ---
if [[ ! -f "$SUPPORT_DIR/watchLater.json" ]]; then
  warn "watchLater.json not found"
else
  python3 - "$SUPPORT_DIR/watchLater.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, list):
        print(f"  ✅ watchLater.json: {len(data)} pinned tracks")
    else:
        print("  ❌ watchLater.json: not a JSON array")
        sys.exit(1)
except json.JSONDecodeError as e:
    print(f"  ❌ watchLater.json: invalid JSON ({e})")
    sys.exit(1)
PY
fi

# --- top-charts.json ---
if [[ ! -f "$SUPPORT_DIR/top-charts.json" ]]; then
  warn "top-charts.json not found (run update-top-music.sh)"
else
  python3 - "$SUPPORT_DIR/top-charts.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, list):
        print(f"  ✅ top-charts.json: {len(data)} genres")
    else:
        print("  ❌ top-charts.json: not a JSON array")
        sys.exit(1)
except json.JSONDecodeError as e:
    print(f"  ❌ top-charts.json: invalid JSON ({e})")
    sys.exit(1)
PY
fi

echo
if ((FAIL)); then
  echo "Validation: FAILED ($FAIL errors, $WARN warnings)"
  exit 1
elif ((WARN)); then
  echo "Validation: OK ($WARN warnings)"
  exit 0
else
  echo "Validation: OK"
  exit 0
fi
#!/usr/bin/env bash
# Verify a macOS FreeTube installation (app, signature, updater, config).
set -uo pipefail

FAIL=0

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; FAIL=1; }
warn() { printf 'WARN  %s\n' "$*"; }
note() { printf 'INFO  %s\n' "$*"; }

APP="${FREETUBE_APP:-}"
if [[ -z "$APP" ]]; then
  for candidate in "$HOME/Applications/FreeTube.app" "/Applications/FreeTube.app"; do
    [[ -d "$candidate" ]] && APP="$candidate" && break
  done
fi

if [[ -z "$APP" ]]; then
  fail "FreeTube.app not found"
else
  note "App: $APP"
fi

if [[ -n "$APP" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)"
  [[ -n "$VERSION" ]] && pass "version $VERSION" || fail "could not read version"

  if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
    pass "code signature valid"
  else
    fail "code signature invalid"
  fi

  if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
    warn "quarantine attribute present; run: xattr -dr com.apple.quarantine '$APP'"
  else
    pass "no quarantine attribute"
  fi
fi

# Updater (per-user installs only).
SCRIPT="$HOME/Library/Scripts/FreeTubeAutoUpdate.sh"
PLIST="$HOME/Library/LaunchAgents/local.freetube.autoupdate.plist"
if [[ -x "$SCRIPT" ]]; then
  pass "updater script present"
else
  note "updater script absent (system-wide installs skip auto-update)"
fi
if [[ -f "$PLIST" ]]; then
  pass "updater LaunchAgent present"
  if launchctl print "gui/$(id -u)/local.freetube.autoupdate" >/dev/null 2>&1; then
    pass "updater LaunchAgent loaded"
  else
    warn "updater LaunchAgent not loaded; run install.sh to register it"
  fi
else
  note "updater LaunchAgent absent"
fi

# Config.
SUPPORT="$HOME/Library/Application Support/FreeTube"
if [[ -f "$SUPPORT/settings.db" ]]; then
  python3 - "$SUPPORT" <<'PY'
import json, pathlib, sys
sup = pathlib.Path(sys.argv[1])
settings = {}
for line in (sup / "settings.db").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except json.JSONDecodeError:
        print("FAIL  settings.db is not valid JSON lines")
        sys.exit(2)
    settings[d.get("_id")] = d.get("value")
def chk(name, expected=None):
    ok = name in settings and (expected is None or settings[name] == expected)
    print(("PASS  " if ok else "WARN  ") + f"setting {name} = {settings.get(name)!r}")
    return ok
chk("backendPreference")
chk("backendFallback", True)
chk("useRssFeeds", True)
chk("checkForUpdates", True)
chk("useProxy", False)

def count_db(name, key=None):
    path = sup / name
    if not path.is_file():
        return 0
    docs = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        d = json.loads(line)
        i = d.get("_id")
        if d.get("$$deleted"):
            docs.pop(i, None)
        else:
            docs[i] = d
    return len(docs)

pl = count_db("playlists.db")
pr = count_db("profiles.db")
print(f"INFO  playlists: {pl}, profiles: {pr}")
sys.exit(0)
PY
  rc=$?
  (( rc == 2 )) && FAIL=1
else
  note "no settings.db (start FreeTube once)"
fi

# Optional media-control helper.
if command -v nowplaying-cli >/dev/null 2>&1; then
  title="$(nowplaying-cli get title 2>/dev/null || true)"
  if [[ -n "$title" ]]; then
    pass "Now Playing active: $title"
  else
    note "nowplaying-cli installed; no media currently playing"
  fi
else
  note "nowplaying-cli not installed (optional; brew install nowplaying-cli)"
fi

if ((FAIL)); then
  echo "verify: FAILED"
  exit 1
fi
echo "verify: OK"

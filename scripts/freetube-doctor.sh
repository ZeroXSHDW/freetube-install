#!/usr/bin/env bash
# FreeTube doctor: local install/config sanity plus network reachability checks.
set -uo pipefail

note() { printf 'INFO  %s\n' "$*"; }
ok() { printf 'OK    %s\n' "$*"; }
bad() { printf 'CHECK %s\n' "$*"; }

APP=""
for candidate in "$HOME/Applications/FreeTube.app" "/Applications/FreeTube.app"; do
  [[ -d "$candidate" ]] && APP="$candidate" && break
done
[[ -z "$APP" ]] && APP="$HOME/Applications/FreeTube.app"

if [[ -d "$APP" ]]; then
  ok "FreeTube.app present ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null))"
else
  bad "FreeTube.app missing"
fi

if [[ -f "$HOME/Library/Logs/FreeTubeAutoUpdate.log" ]]; then
  ok "updater log exists"
  note "$(tail -n 2 "$HOME/Library/Logs/FreeTubeAutoUpdate.log" | sed 's/^/        /')"
else
  note "no updater log yet"
fi

# Network reachability.
if curl -sI --max-time 10 https://www.youtube.com >/dev/null 2>&1; then
  ok "https://www.youtube.com reachable"
else
  bad "YouTube not reachable from this network"
fi

if curl -s --max-time 15 'https://api.invidious.io/instances.json?sort_by=health' >/dev/null 2>&1; then
  ok "api.invidious.io reachable"
else
  bad "Invidious instance list not reachable"
fi

# A healthy public instance, if any, for fallback diagnostics.
health_json="$(curl -s --max-time 15 'https://api.invidious.io/instances.json?sort_by=health' 2>/dev/null || true)"
if [[ -n "$health_json" ]]; then
  first="$(printf '%s' "$health_json" | python3 -c '
import json,sys
try:
    data=json.load(sys.stdin)
except Exception:
    sys.exit(0)
for host, info in data:
    if info.get("api") and "onion" not in host and "i2p" not in host:
        print(info.get("uri","").rstrip("/"))
        break
')"
  if [[ -n "$first" ]]; then
    note "top healthy Invidious instance: $first"
  fi
fi

# Config summary.
SUPPORT="$HOME/Library/Application Support/FreeTube"
if [[ -f "$SUPPORT/settings.db" ]]; then
  python3 - "$SUPPORT" <<'PY'
import json, pathlib, sys
sup = pathlib.Path(sys.argv[1])
settings = {}
for line in (sup / "settings.db").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line and (d := json.loads(line)):
        settings[d.get("_id")] = d.get("value")
print("        backend:", settings.get("backendPreference"), "| fallback:", settings.get("backendFallback"),
      "| rss:", settings.get("useRssFeeds"), "| proxy:", settings.get("useProxy"))
print("        format:", settings.get("defaultVideoFormat"), "| quality:", settings.get("defaultQuality"))
PY
else
  note "no settings.db yet"
fi

if command -v nowplaying-cli >/dev/null 2>&1; then
  t="$(nowplaying-cli get title 2>/dev/null || true)"
  [[ -n "$t" ]] && ok "Now Playing: $t" || note "nothing playing right now"
fi

cat <<'ADVICE'

If a specific video fails to play:
  1. Press play again (expired stream URLs are re-extracted).
  2. If the toast says "IP block", enable a VPN or proxy, or switch the API
     backend in Settings → General.
  3. If it says "Video unavailable" / "Private" / "live stream recording",
     remove the entry from the playlist — no backend can play it.
  4. Pick another Invidious instance in Settings → General if fallback fails.
  5. Run the installer repo's install.sh to update FreeTube.

See docs/troubleshooting-playback.md in freetube-configs-main for full steps.
ADVICE

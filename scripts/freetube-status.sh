#!/usr/bin/env bash
# freetube-status — one-shot dashboard showing FreeTube's health,
# playlists, LaunchAgents, and currently playing track.
set -uo pipefail

bold()   { printf '\033[1m%s\033[0m' "$*"; }
ok()     { printf '  ✅ %s\n' "$*"; }
bad()    { printf '  ❌ %s\n' "$*"; }
note()   { printf '  ℹ️  %s\n' "$*"; }

APP=""
for candidate in "$HOME/Applications/FreeTube.app" "/Applications/FreeTube.app"; do
  [[ -d "$candidate" ]] && APP="$candidate" && break
done

echo
bold "FreeTube Status Dashboard"
echo "========================="
echo

# --- App ---
bold "App:"
if [[ -n "$APP" && -d "$APP" ]]; then
  VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "unknown")"
  ok "FreeTube.app v$VER at $APP"
else
  bad "FreeTube.app not found"
fi

# --- LaunchAgents ---
bold "LaunchAgents:"
UID_NUM="$(id -u)"
for agent in local.freetube.autoupdate local.freetube.topmusic local.freetube.bar \
             local.freetube.resume local.freetube.audiopause; do
  if launchctl print "gui/$UID_NUM/$agent" >/dev/null 2>&1; then
    ok "$agent loaded"
  else
    bad "$agent not loaded"
  fi
done

# --- Scripts ---
bold "Helper scripts:"
for script in freetube-autoupdate.sh update-top-music.sh play-genre.sh resume-last.sh \
              play-favorites.sh play-watch-later.sh audio-pause.sh freetube-doctor.sh \
              freetube-status.sh freetube-backup.sh freetube-cleanup.sh; do
  if [[ -x "$HOME/Library/Scripts/$script" ]]; then
    ok "$script"
  else
    bad "$script missing"
  fi
done

# --- Menu bar app ---
bold "Menu bar app:"
if [[ -x "$HOME/Library/Application Support/FreeTubeBar/FreeTubeBar" ]]; then
  ok "FreeTubeBar present"
else
  bad "FreeTubeBar missing (build with swiftc)"
fi
if [[ -x "$HOME/Library/Application Support/FreeTubeBar/audiodevice" ]]; then
  ok "audiodevice helper present"
else
  bad "audiodevice helper missing"
fi

# --- nowplaying-cli ---
bold "Media controls:"
if command -v nowplaying-cli >/dev/null 2>&1; then
  title="$(nowplaying-cli get title 2>/dev/null || true)"
  rate="$(nowplaying-cli get playbackRate 2>/dev/null || true)"
  if [[ -n "$title" ]]; then
    ok "Now Playing: $title (rate=$rate)"
  else
    note "nowplaying-cli installed; nothing playing"
  fi
else
  bad "nowplaying-cli not installed (brew install nowplaying-cli)"
fi

# --- Playlists ---
bold "Playlists:"
SUPPORT="$HOME/Library/Application Support/FreeTube"
if [[ -f "$SUPPORT/playlists.db" ]]; then
  python3 - "$SUPPORT" <<'PY'
import json, pathlib, sys
sup = pathlib.Path(sys.argv[1])
docs, order = {}, []
for line in (sup / "playlists.db").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line: continue
    try: d = json.loads(line)
    except json.JSONDecodeError: continue
    i = d.get("_id")
    if d.get("$$deleted"):
        docs.pop(i, None); order.remove(i) if i in order else None
        continue
    if i not in order: order.append(i)
    docs[i] = d
managed = [d for d in order if docs[d].get("playlistName", "").startswith("Top Charts —")]
user = [d for d in order if not docs[d].get("playlistName", "").startswith("Top Charts —")]
print(f"    {len(managed)} Top Charts playlists (auto-updated)")
print(f"    {len(user)} user playlists")
for pid in managed[:18]:
    d = docs[pid]
    vs = [v for v in d.get("videos", []) if v.get("videoId")]
    print(f"    • {d.get('playlistName', pid)} — {len(vs)} tracks")
PY
else
  bad "playlists.db not found (start FreeTube once)"
fi

# --- Config files ---
bold "Config files:"
for f in settings.db favorites.json watchLater.json last-genre.json top-charts.json; do
  if [[ -f "$SUPPORT/$f" ]]; then
    ok "$f"
  else
    note "$f not present"
  fi
done

# --- Logs ---
bold "Recent logs:"
for log in FreeTubeAutoUpdate.log FreeTubeTopMusic.log FreeTubeAirPods.log; do
  path="$HOME/Library/Logs/$log"
  if [[ -f "$path" ]]; then
    last="$(tail -n 1 "$path" 2>/dev/null || true)"
    note "$log: $last"
  else
    note "$log: not yet created"
  fi
done

echo
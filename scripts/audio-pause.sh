#!/usr/bin/env bash
# Watch the default audio output device and pause FreeTube when AirPods /
# Bluetooth headphones are removed (so music doesn't blast from the speakers).
set -uo pipefail

BIN="$HOME/Library/Application Support/FreeTubeBar/audiodevice"
NP=""
for c in /opt/homebrew/bin/nowplaying-cli /usr/local/bin/nowplaying-cli; do
  [[ -x "$c" ]] && NP="$c" && break
done
[[ -z "$NP" ]] && NP="nowplaying-cli"

LOG="$HOME/Library/Logs/FreeTubeAirPods.log"
mkdir -p "$HOME/Library/Logs"
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

is_headphones() { [[ "$1" =~ (AirPods|Beats|Headphone|Headset|Buds|JBL|Sony|Bose|Sennheiser|Soundcore|Bluetooth) ]]; }
is_builtin() { [[ "$1" =~ (MacBook|Speaker|Internal|Built-?in|Built In) ]]; }

is_freetube_playing() {
  [[ "$($NP get playbackRate 2>/dev/null)" == "1" ]] || return 1
  $NP get-raw 2>/dev/null | grep -q 'io.freetubeapp.freetube'
}

[[ -x "$BIN" ]] || { log "audiodevice helper missing at $BIN"; exit 1; }

prev=""
while true; do
  dev="$("$BIN" 2>/dev/null || true)"
  if [[ -n "$prev" && -n "$dev" && "$prev" != "$dev" ]]; then
    if is_headphones "$prev" && is_builtin "$dev" && is_freetube_playing; then
      log "Headphones removed ($prev -> $dev); pausing FreeTube."
      "$NP" pause 2>/dev/null || true
    fi
  fi
  prev="$dev"
  sleep 3
done

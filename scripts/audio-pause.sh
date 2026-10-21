#!/usr/bin/env bash
# Watch the default audio output device and pause/resume FreeTube when
# AirPods / Bluetooth headphones are connected or disconnected.
#
# Pause when headphones are removed (so music doesn't blast from speakers).
# Resume when headphones are reconnected (if FreeTube was playing before).
set -uo pipefail

BIN="$HOME/Library/Application Support/FreeTubeBar/audiodevice"
NP=""
for c in /opt/homebrew/bin/nowplaying-cli /usr/local/bin/nowplaying-cli; do
  [[ -x "$c" ]] && NP="$c" && break
done
[[ -z "$NP" ]] && NP="nowplaying-cli"

CHECK_INTERVAL="${FREETUBE_AUDIO_CHECK_INTERVAL:-3}"
LOG="$HOME/Library/Logs/FreeTubeAirPods.log"
STATE_DIR="$HOME/Library/Application Support/FreeTube"
STATE_FILE="$STATE_DIR/.audiopause-state"
mkdir -p "$HOME/Library/Logs" "$STATE_DIR"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

is_headphones() {
  [[ "$1" =~ (AirPods|Beats|Headphone|Headset|Buds|JBL|Sony|Bose|Sennheiser|Soundcore|Bluetooth|WH|WF|QuietComfort|Momentum) ]]
}
is_builtin() {
  [[ "$1" =~ (MacBook|Speaker|Internal|Built-?in|Built In|Internal Speakers) ]]
}

is_freetube_playing() {
  local rate
  rate="$("$NP" get playbackRate 2>/dev/null || true)"
  [[ "$rate" == "1" ]] || return 1
  "$NP" get-raw 2>/dev/null | grep -q 'io.freetubeapp.freetube'
}

[[ -x "$BIN" ]] || { log "audiodevice helper missing at $BIN"; exit 1; }

prev=""
was_playing_when_paused=0
while true; do
  dev="$("$BIN" 2>/dev/null || true)"
  if [[ -n "$prev" && -n "$dev" && "$prev" != "$dev" ]]; then
    # Headphones removed -> built-in speakers
    if is_headphones "$prev" && is_builtin "$dev"; then
      if is_freetube_playing; then
        log "Headphones removed ($prev -> $dev); pausing FreeTube."
        "$NP" pause 2>/dev/null || true
        was_playing_when_paused=1
        echo "1" >"$STATE_FILE"
      fi
    # Headphones connected -> some headphone device
    elif is_builtin "$prev" && is_headphones "$dev"; then
      if [[ "$was_playing_when_paused" == "1" ]]; then
        log "Headphones reconnected ($prev -> $dev); resuming FreeTube."
        "$NP" play 2>/dev/null || true
        was_playing_when_paused=0
        echo "0" >"$STATE_FILE"
      fi
    fi
  fi
  prev="$dev"
  sleep "$CHECK_INTERVAL"
done
#!/usr/bin/env bash
# freetube-launchctl — enable/disable/status FreeTube LaunchAgents.
#
# Usage: freetube-launchctl <enable|disable|status|restart> [agent]
#
# Agents:
#   autoupdate   FreeTube auto-updater (login + every 6 h)
#   topmusic     Top Charts refresh (every 6 h)
#   bar          ♫ FreeTubeBar menu bar app
#   resume       Resume last genre on login
#   audiopause   AirPods auto-pause watcher
#   installer    Native Swift add-on app (FreeTubeInstaller)
#   all          All agents
set -euo pipefail

LAUNCH_DIR="$HOME/Library/LaunchAgents"
UID_NUM="$(id -u)"

AGENTS=(
  "autoupdate:local.freetube.autoupdate"
  "topmusic:local.freetube.topmusic"
  "bar:local.freetube.bar"
  "resume:local.freetube.resume"
  "audiopause:local.freetube.audiopause"
  "installer:local.freetube.installer"
)

usage() {
  cat <<'USAGE'
Usage: freetube-launchctl <command> [agent]

Commands:
  enable   [agent]  Enable and load a LaunchAgent (or 'all')
  disable  [agent]  Disable and unload a LaunchAgent (or 'all')
  status   [agent]  Show whether a LaunchAgent is loaded (or 'all')
  restart  [agent]  Restart a LaunchAgent (or 'all')

Agents: autoupdate, topmusic, bar, resume, audiopause, installer, all
USAGE
  exit 0
}

agent_exists() {
  local name="$1"
  [[ -f "$LAUNCH_DIR/$name.plist" ]]
}

agent_loaded() {
  local name="$1"
  launchctl print "gui/$UID_NUM/$name" >/dev/null 2>&1
}

do_enable() {
  local name="$1"
  local plist="$LAUNCH_DIR/$name.plist"
  if [[ ! -f "$plist" ]]; then
    echo "❌ $name: plist not found at $plist"
    return 1
  fi
  launchctl bootout "gui/$UID_NUM/$name" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_NUM" "$plist" 2>/dev/null || true
  launchctl enable "gui/$UID_NUM/$name" 2>/dev/null || true
  if agent_loaded "$name"; then
    echo "✅ $name: enabled and loaded"
  else
    echo "⚠️  $name: enabled but not loaded (check console logs)"
  fi
}

do_disable() {
  local name="$1"
  launchctl bootout "gui/$UID_NUM/$name" 2>/dev/null || true
  launchctl disable "gui/$UID_NUM/$name" 2>/dev/null || true
  if agent_loaded "$name"; then
    echo "⚠️  $name: disabled but still loaded"
  else
    echo "✅ $name: disabled and unloaded"
  fi
}

do_status() {
  local name="$1"
  local plist="$LAUNCH_DIR/$name.plist"
  if [[ ! -f "$plist" ]]; then
    echo "❌ $name: plist not found"
    return
  fi
  if agent_loaded "$name"; then
    echo "✅ $name: loaded"
  else
    echo "❌ $name: not loaded"
  fi
}

do_restart() {
  local name="$1"
  do_disable "$name"
  sleep 1
  do_enable "$name"
}

resolve_agent() {
  local input="$1"
  for entry in "${AGENTS[@]}"; do
    local short="${entry%%:*}"
    local full="${entry##*:}"
    if [[ "$input" == "$short" || "$input" == "$full" ]]; then
      echo "$full"
      return 0
    fi
  done
  if [[ "$input" == "all" ]]; then
    echo "all"
    return 0
  fi
  return 1
}

if (($# < 1)); then
  usage
fi

CMD="$1"
AGENT_INPUT="${2:-all}"

case "$CMD" in
  enable|disable|status|restart) ;;
  -h|--help) usage ;;
  *) echo "Unknown command: $CMD" >&2; usage >&2; exit 2 ;;
esac

AGENT_NAME="$(resolve_agent "$AGENT_INPUT")" || {
  echo "Unknown agent: $AGENT_INPUT" >&2
  echo "Available: autoupdate, topmusic, bar, resume, audiopause, installer, all" >&2
  exit 2
}

if [[ "$AGENT_NAME" == "all" ]]; then
  for entry in "${AGENTS[@]}"; do
    name="${entry##*:}"
    case "$CMD" in
      enable)   do_enable "$name" ;;
      disable)  do_disable "$name" ;;
      status)   do_status "$name" ;;
      restart)  do_restart "$name" ;;
    esac
  done
else
  case "$CMD" in
    enable)   do_enable "$AGENT_NAME" ;;
    disable)  do_disable "$AGENT_NAME" ;;
    status)   do_status "$AGENT_NAME" ;;
    restart)  do_restart "$AGENT_NAME" ;;
  esac
fi
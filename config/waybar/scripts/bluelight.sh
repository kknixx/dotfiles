#!/usr/bin/env bash
# Waybar custom module: blue-light filter (sunsetr) toggle.
#   (no args)  -> status: line 1 = icon, line 2 = tooltip (re-run on interval)
#   toggle     -> flip on/off (wired to on-click)
#
# State is read via `pgrep -x sunsetr` — the `sunsetr status` IPC is flaky
# (reports "no process running" while one is), so the process check is the source of truth.
set -u

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
LOCK="$RUNTIME_DIR/sunsetr.lock"

running() { pgrep -x sunsetr >/dev/null 2>&1; }

# Kill every lingering sunsetr scope + process (defensive; 'stop' alone is flaky).
kill_all() {
  for s in $(systemctl --user list-units --type=scope --no-legend 2>/dev/null | grep -i sunsetr | awk '{print $1}'); do
    systemctl --user stop "$s" 2>/dev/null || true
  done
  for p in $(pgrep -x sunsetr); do kill "${1:-9}" "$p" 2>/dev/null || true; done
  rm -f "$LOCK"
}

turn_on() {
  kill_all          # clean slate so we never stack two instances
  sunsetr --background >/dev/null 2>&1   # spawns into app-niri-sunsetr-<pid>.scope
}

turn_off() {
  sunsetr stop >/dev/null 2>&1 || true   # clean path first
  sleep 0.5
  kill_all 9       # force-kill anything that survived (scope + SIGKILL)
}

case "${1:-status}" in
  toggle)
    if running; then turn_off; else turn_on; fi
    ;;
  *)
    # Nerd Font glyphs, same as the bar's other custom modules (sysinfo/netinfo/help).
    # Trailing space: the PUA ink overhangs its advance and GTK clips the label
    # width, so pad it. (A themed <img> icon is not possible here — GTK label
    # markup has no image tag, and the fork's image-name config is static.)
    if running; then
      printf '\uf186 '   # fa-moon_o  = filter ON  (warm / night)
    else
      printf '\U000f0599 '  # md-weather_sunny = filter OFF (normal / day); \U + 8 hex digits
    fi
    ;;
esac

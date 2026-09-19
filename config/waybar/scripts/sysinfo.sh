#!/usr/bin/env bash
# Waybar custom module: live CPU% · MEM% · CPU temp · GPU temp.
# Light by design — reads /proc + sysfs only, plus one nvidia-smi query per run.
set -u

RED="#f38ba8"          # alert colour (catppuccin red)
cache="$HOME/.cache/waybar-sysinfo-cpustat"

# --- CPU usage: delta of /proc/stat since last run ---
read -r _ u n s i io irq sirq st _ < /proc/stat
total=$((u+n+s+i+io+irq+sirq+st))
idle=$((i+io))
cpu="--"
if [ -f "$cache" ]; then
  read -r lt li < "$cache"
  dt=$((total-lt)); di=$((idle-li))
  [ "$dt" -gt 0 ] && cpu=$((100*(dt-di)/dt))
fi
printf '%s %s\n' "$total" "$idle" > "$cache"

# --- Memory: /proc/meminfo ---
mem="--"; mt=0; ma=0
while read -r k v _; do
  case "$k" in
    MemTotal:)     mt=$v ;;
    MemAvailable:) ma=$v ;;
  esac
done < /proc/meminfo
[ "$mt" -gt 0 ] && mem=$((100*(mt-ma)/mt))

# --- CPU temp: k10temp hwmon ---
cput="--"
for d in /sys/class/hwmon/hwmon*; do
  [ "$(cat "$d/name" 2>/dev/null)" = "k10temp" ] && \
    cput=$(( $(cat "$d/temp1_input" 2>/dev/null) / 1000 )) && break
done

# --- GPU temp: nvidia-smi (one-shot) ---
gput="--"
if command -v nvidia-smi >/dev/null 2>&1; then
  g=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
  [ -n "$g" ] && gput=$g
fi

# colour a value red when it crosses its threshold ("--" stays plain)
cnum() { # $1=value $2=threshold
  if [ "$1" != "--" ] && [ "$1" -ge "$2" ]; then
    printf '<span foreground="%s">%s</span>' "$RED" "$1"
  else
    printf '%s' "$1"
  fi
}

# Waybar custom contract: line 1 = label, line 2 = tooltip, line 3 = css class.
# Compact label first (with red threshold spans), detail tooltip second.
# fa-microchip (CPU) + fa-memory (RAM): same Nerd Font set, so equal size,
# space after each icon prevents glyph bearing overlap.
printf '\uf2db %s%%  \uefc5 %s%%  %s°/%s°\n' \
  "$(cnum "$cpu" 85)" "$(cnum "$mem" 85)" "$(cnum "$cput" 80)" "$(cnum "$gput" 80)"
printf 'CPU %s%% · MEM %s%% · CPU temp %s°C · GPU temp %s°C' "$cpu" "$mem" "$cput" "$gput"

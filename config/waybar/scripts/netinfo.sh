#!/usr/bin/env bash
# Waybar custom module: animated up/down network speed for the active interface.
# Reads /proc/net/dev only — no daemons, no extra tools. 1s interval = smooth.
set -u
IFACE="enp37s0"
cache="$HOME/.cache/waybar-netinfo-cnt"

# rx_bytes = field 2, tx_bytes = field 10 of the iface line
read -r rb tb < <(awk -F' *:' -v i="$IFACE" '$1==i{print $2}' /proc/net/dev | awk '{print $1, $9}')
[ -z "$rb" ] && exit 0

now=$(date +%s)
if [ -f "$cache" ]; then
  read -r pt pr ptb < "$cache"
  dt=$((now - pt))
  if [ "$dt" -ge 1 ]; then
    du=$(( (tb - ptb) / dt )); dr=$(( (rb - pr) / dt ))
    [ "$du" -lt 0 ] && du=0
    [ "$dr" -lt 0 ] && dr=0
  fi
fi
printf '%s %s %s\n' "$now" "$rb" "$tb" > "$cache"

fmt() { # bytes/s -> human
  local b=$1
  if   [ "$b" -ge 1048576 ]; then awk -v x="$b" 'BEGIN{printf "%.1fM", x/1048576}'
  elif [ "$b" -ge 1024 ];    then awk -v x="$b" 'BEGIN{printf "%.0fK", x/1024}'
  else                             printf '%d' "$b"
  fi
}


du=${du:-0}; dr=${dr:-0}

# minimal label: bare arrows — red while uploading, teal while downloading.
arw() { # $1=arrow $2=speed $3=color
  if [ "$2" -ge 1024 ]; then printf '<span foreground="%s">%s</span>' "$3" "$1"
  else printf '%s' "$1"; fi
}
printf '%s %s\n' "$(arw '↑' "$du" '#f38ba8')" "$(arw '↓' "$dr" '#5eead4')"
printf '↑ %s/s   ↓ %s/s   (%s)' "$(fmt "$du")" "$(fmt "$dr")" "$IFACE"

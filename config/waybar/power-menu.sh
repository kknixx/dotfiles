#!/bin/sh
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
# Power menu: opens at the top-right of the output (below the waybar
# power icon). wofi --location top_right anchors there natively.

WIDTH=120     # menu width (px)
BAR_H=40      # waybar height (px) + a little breathing room

choice=$(wofi --show dmenu --title "Power" --width "$WIDTH" \
    --location top_right --yoffset "$BAR_H" <<EOF
Logout
Suspend
Reboot
Power Off
EOF
) || exit 0

case "$choice" in
  Logout)
    # niri's quit with confirmation skipped returns to the login manager.
    niri msg action quit --skip-confirmation 2>/dev/null
    ;;
  Suspend)
    systemctl suspend
    ;;
  Reboot)
    systemctl reboot
    ;;
  "Power Off")
    systemctl poweroff
    ;;
esac

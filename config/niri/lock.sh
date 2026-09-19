#!/bin/sh
# GDM-style screen lock for niri: capture the live screen, blur + dim it,
# and feed it to swaylock as the background image.
# Plain swaylock (no -effects build) so we DIY the blur via grim + ImageMagick.

set -eu

out="HDMI-A-2"
shot="/tmp/niri-lock-${out}.png"

# Capture the current screen. -o specific output avoids multi-monitor surprises.
grim -o "$out" -t png "$shot"

# Blur + darken, GDM-style: 0x13 box blur (~swaylock-effects effect-blur=13x13)
# then dim 45% toward black to simulate effect-vignette dimming.
magick "$shot" \
    -blur 0x13 \
    -fill black -colorize 45 \
    "$shot"

# Plain-swaylock-compatible config. Kept inline so the legacy
# ~/.config/swaylock/config (swaylock-effects directives, breaks plain build)
# is never loaded. Colours: Dracula, matching the old config.
lock_conf="/tmp/niri-swaylock.conf"
cat > "$lock_conf" <<'EOF'
ignore-empty-password
show-failed-attempts
color=282A36
font=Inter
indicator-radius=200
indicator-thickness=20
line-color=282A36
ring-color=BD93F9
inside-color=282A36
key-hl-color=50FA7B
separator-color=00000000
text-color=F8F8F2
line-ver-color=BD93F9
ring-ver-color=BD93F9
inside-ver-color=282A36
text-ver-color=8BE9FD
ring-wrong-color=FF5555
text-wrong-color=FF5555
inside-wrong-color=282A36
inside-clear-color=282A36
text-clear-color=8BE9FD
ring-clear-color=8BE9FD
line-clear-color=8BE9FD
line-wrong-color=282A36
bs-hl-color=8BE9FD
EOF

# NB: no auto DPMS/power-off timer here. GPU power-off (niri
# power-off-monitors) bricked the display on nvidia-drm modeset=1 (NVKMS
# GEM alloc failure on monitor wake → hard reset). Locking stays on.
cleanup() {
    rm -f "$shot" "$lock_conf"
}
trap cleanup EXIT INT TERM

# Foreground: blocks until the user authenticates. -c is a fallback colour
# in case the image path somehow fails to load.
swaylock -C "$lock_conf" -i "${out}:${shot}" -s fill -c 282A36

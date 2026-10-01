#!/usr/bin/env bash
# Waybar custom module: battery level of connected Bluetooth devices,
# Ampere-style "device-icon + battery-glyph + percent" per device.
# A segment appears only while its device is connected; the module is
# blank when nothing is connected. BlueZ publishes BT batteries through
# upower, so upower is the only source — no bluez D-Bus plumbing.
# Contract: line 1 = label, line 2 = tooltip (see sysinfo.sh).
# Arg picks the device class: "audio" (buds/headphones), "other" (mouse,
# keyboard, anything unclassified), "all". Waybar has one tooltip per module,
# so audio and input live in separate module instances to keep hover honest.
set -u

YEL="#f9e2af"; RED="#f38ba8"
# Battery glyphs indexed by round(pct/10). Codepoints are THIS font's own
# map (Nerd Font remaps upstream mdi values) — resolved by glyph name from
# CaskaydiaMonoNerdFont-Regular.ttf via fontTools; don't "correct" them to
# upstream mdi numbers. Same for icon() below.
bat=($'\U000F0079' $'\U000F007A' $'\U000F007B' $'\U000F007C' $'\U000F007D'
     $'\U000F007E' $'\U000F007F' $'\U000F0080' $'\U000F0081' $'\U000F0082')

AUDIO='headset_dev|phone_dev|tablet_dev'
want=${1:-other}

# device-class icon from the upower native path
icon() {
  case $1 in
    *mouse_dev*)                            printf '\U000F037F' ;;  # md-mouse_variant
    *keyboard_dev*)                         printf '\U000F030C' ;;  # md-keyboard
    *headset_dev*|*phone_dev*|*tablet_dev*) printf '\U000F184F' ;;  # md-earbuds
    *)                                      printf '\U000F00AF' ;;  # md-bluetooth
  esac
}

label=""; tip=""
for d in $(upower --enumerate | tr ' ' '\n' | grep -E '_dev_[0-9A-F]'); do
  case $want in
    audio)       grep -qE "$AUDIO" <<<"$d" || continue ;;
    other)       grep -qE "$AUDIO" <<<"$d" && continue ;;
  esac

  info=$(upower -i "$d")
  p=$(sed -n 's/^ *percentage: *\([0-9.]*\).*/\1/p' <<<"$info" | head -1)
  [ -z "$p" ] && continue                     # battery still unknown
  name=$(sed -n 's/^ *model: *//p'    <<<"$info" | head -1)
  [ -z "$name" ] && name=$(sed -n 's/^ *serial: *//p' <<<"$info" | head -1)
  p=${p%%.*}

  i=$(( (p + 5) / 10 )); (( i > 9 )) && i=9
  # no percentage text — the glyph's fill level is the readout, exact % on
  # hover. Low-battery colour moves onto the glyph so the signal survives.
  b=${bat[i]}
  if   [ "$p" -le 10 ]; then b="<span foreground=\"$RED\">$b</span>"
  elif [ "$p" -le 20 ]; then b="<span foreground=\"$YEL\">$b</span>"
  fi
  # Spacing via label spaces, not CSS: this waybar fork's id selector
  # #custom-btbat-audio never matched, so margin edits changed nothing.
  label="${label:+$label }$(icon "$d") $b"
  tip+="${tip:+\n}${name:-Bluetooth} ${p}%"
done

# ponytail: laptop battery segment from the Ampere reference is omitted —
# waybar's own #battery module already covers it. Add BAT0 to the loop if wanted.
# One space each side: module1's pad + module2's pad = 2 spaces between
# devices (CSS margins don't apply in this fork, see note above).
[ -n "$label" ] && printf ' %s \n%b\n' "$label" "$tip"

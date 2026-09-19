#!/bin/bash
# niri app switcher (migrated from sway's app_switcher.sh)
# Lists open windows via `niri msg windows --json` and focuses the picked one.
windows=$(niri msg windows --json | jq -r '.[] | "\(.id)\t\(.app_id // "app")\t\(.title // "untitled")"')
selected=$(echo "$windows" | awk -F'\t' 'NF>1 {printf "%d\t%s - %s\n", $1, $2, $3}' | wofi --show dmenu --prompt "Switch to:")
id=$(echo "$selected" | cut -f1)
if [ -n "$id" ]; then
    niri msg action focus-window --id "$id"
fi

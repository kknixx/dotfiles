#!/bin/sh
# Keybind cheat-sheet: parses the live config.kdl via keybinds-help.py and
# shows it in a floating foot window (less). Bound to Mod+/ — replaces the
# built-in hotkey-overlay, which only lists niri's inbuilt actions.
# The wait loop lets foot finish applying -W before less measures the tty
# (less otherwise sees the default 24 rows and paints a half page).
foot -a niri-keybinds -W 96x40 -f 'CaskaydiaMono Nerd Font:size=12' -e sh -c \
  'i=0; while [ "$(stty size 2>/dev/null | cut -d" " -f1)" != "40" ] && [ $i -lt 100 ]; do sleep 0.05; i=$((i+1)); done; python3 ~/.config/niri/keybinds-help.py | LESSKEYIN=$HOME/.config/niri/lesskeys less -R -X'

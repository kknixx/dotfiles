#!/usr/bin/env python3
"""Classified keybind reference for niri, parsed live from config.kdl."""
import re
from pathlib import Path

CFG = Path.home() / ".config/niri/config.kdl"

HUMAN = {
    "toggle-overview": "Open overview",
    "close-window": "Close window",
    "quit": "Quit niri (confirm)",
    "maximize-window-to-edges": "Maximize window to screen edges",
    "fullscreen-window": "Toggle fullscreen",
    "toggle-column-tabbed-display": "Toggle tabbed column display",
    "toggle-window-floating": "Toggle floating",
    "switch-focus-between-floating-and-tiling": "Switch focus: floating / tiling",
    "switch-preset-column-width": "Cycle column-width presets",
    "switch-preset-column-width-back": "Cycle column-width presets (reverse)",
    "center-column": "Center focused column",
    "screenshot": "Screenshot (pick area)",
    "screenshot-screen": "Screenshot: full screen",
    "screenshot-window": "Screenshot: window",
    "show-hotkey-overlay": "Built-in keybind overlay",
    "toggle-keyboard-shortcuts-inhibit": "Toggle keyboard-shortcuts inhibit",
}

KEYS = {
    "XF86AudioMute": "Mute audio",
    "XF86AudioLowerVolume": "Volume down",
    "XF86AudioRaiseVolume": "Volume up",
    "XF86AudioMicMute": "Mic mute",
    "XF86MonBrightnessDown": "Brightness down",
    "XF86MonBrightnessUp": "Brightness up",
}


def describe(tok: str) -> str:
    tok = tok.strip().rstrip(";")
    parts = tok.split(None, 1)
    name = parts[0]
    rest = parts[1].strip() if len(parts) > 1 else ""
    args = re.findall(r'"([^"]*)"|(?<![\s"=])(\w+)', rest)
    args = [a or b for a, b in args]
    if name in ("spawn", "spawn-sh"):
        cmd = " ".join(args)
        for needle, text in (
            ("lock", "Lock screen"),
            ("poweroff", "Power off"),
            ("reboot", "Reboot"),
            ("wofi", "App launcher"),
            ("nwg-dock", "Toggle dock"),
            ("app_switcher", "App switcher"),
            ("brightnessctl", "Brightness " + cmd.rsplit(" ", 1)[-1]),
        ):
            if needle in cmd:
                return text
        return "Run: " + cmd
    if name == "set-column-width":
        return f"Column width {args[0] if args else ''}"
    if name == "focus-workspace":
        return f"Go workspace {args[0]}"
    if name == "move-column-to-workspace":
        return f"Move to workspace {args[0]} and switch"
    if name == "focus-workspace-previous":
        return "Previous workspace"
    m = re.match(r"(focus|move)-(column|window)-(left|right|up|down)", name)
    if m:
        verb = "Focus" if m.group(1) == "focus" else "Move"
        return f"{verb} {m.group(2)} {m.group(3)}"
    return HUMAN.get(name, name.replace("-", " ").capitalize())


def parse() -> list[tuple[str, list[tuple[str, str]]]]:
    body = re.search(r"^\s*binds\s*\{(.*?)^\}", CFG.read_text(), re.M | re.S).group(1)
    sections: list[tuple[str, list[tuple[str, str]]]] = []
    header, prev_comment = "General", False
    for raw in body.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("//"):
            if not prev_comment:
                t = line[2:].strip()
                for sep in (":", " (", "."):
                    t = t.split(sep)[0]
                t = t.strip()
                if t and not t.startswith("("):
                    header = t
            prev_comment = True
            continue
        prev_comment = False
        bm = re.match(r"^(.*?)\s*\{(.*)\}\s*$", line)
        if not bm:
            continue
        keys = KEYS.get(bm.group(1).split()[0], bm.group(1).split()[0].replace("Mod", "Super"))
        sections.append((header, [(keys, describe(bm.group(2)))]))
    # merge consecutive same-header sections
    merged: list[tuple[str, list[tuple[str, str]]]] = []
    for h, entries in sections:
        if merged and merged[-1][0] == h:
            merged[-1][1].extend(entries)
        else:
            merged.append((h, entries))
    return merged


def main() -> None:
    out = [f"\033[1mNIRI KEYBINDS\033[0m", "─" * 64]
    for title, entries in parse():
        out += ["", f"\033[1;36m{title}\033[0m"]
        for k, d in entries:
            out.append(f"  {k:<24}{d}")
    print("\n".join(out))


if __name__ == "__main__":
    main()

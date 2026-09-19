#!/usr/bin/env python3
"""niri ws_toggle: toggle-focus a numbered workspace.

Usage: ws_toggle.py <workspace-name>

Press Mod+N once -> focus workspace N (remembering where you were).
Press Mod+N again (while on N) -> return to the remembered workspace.
Press it a third time -> back to N. A two-state back-and-forth on the
same key, which native `focus-workspace N` can't do (it no-ops when you
are already there).

State (target -> previous workspace name) lives in a JSON file so it
survives across key presses. Key presses are serial, so no locking.
"""
import json
import os
import pathlib
import subprocess
import sys


def focused_name():
    """Return the name of the currently focused workspace."""
    out = subprocess.run(
        ["niri", "msg", "--json", "workspaces"],
        capture_output=True, text=True, check=True).stdout
    d = json.loads(out)
    ws = d["workspaces"] if isinstance(d, dict) and "workspaces" in d else d
    for w in ws:
        if w.get("is_focused") or w.get("is_active"):
            return w.get("name")
    return None


def main():
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <workspace-name>", file=sys.stderr)
        sys.exit(2)
    target = sys.argv[1]

    state_file = pathlib.Path(os.environ.get(
        "NIRI_WS_TOGGLE_STATE",
        str(pathlib.Path.home() / ".local/state/niri-ws_toggle.json")))
    state = {}
    if state_file.exists():
        try:
            state = json.loads(state_file.read_text())
        except (ValueError, OSError):
            state = {}

    cur = focused_name()
    prev = state.get(target)

    if cur == target:
        if prev is not None and prev != target:
            dest = prev  # on the target, press again -> go back
        else:
            dest = None  # already on the target, nothing to toggle to
    else:
        dest = target    # go to the target, remember where we are now
        if cur is not None:
            state[target] = cur
            state_file.parent.mkdir(parents=True, exist_ok=True)
            state_file.write_text(json.dumps(state))

    if dest is not None:
        subprocess.run(
            ["niri", "msg", "action", "focus-workspace", str(dest)],
            capture_output=True, text=True, check=False)


if __name__ == "__main__":
    main()

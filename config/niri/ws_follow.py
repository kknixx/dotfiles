#!/usr/bin/env python3
"""niri ws_follow: auto-switch to a workspace when a rule-pinned window
is opened or moved there (Mod+Shift+N, dragging, etc.).

niri 26.04 window-rules have open-on-workspace but no "follow it" option,
so this helper watches `niri msg event-stream --json` and issues
`niri msg action focus-workspace` for pinned apps.

Rules are parsed from config.kdl (single source of truth) and re-read
when the file changes. A 2s bootstrap at (re)connect ignores
"new window" events so logging in doesn't jump you to a workspace.
New/moved windows are debounced 250ms so open+relocate bursts resolve
to one switch. Single instance enforced with an flock.
"""
import fcntl
import json
import os
import pathlib
import re
import subprocess
import sys
import threading
import time

CFG = pathlib.Path.home() / ".config/niri/config.kdl"
LOCK = pathlib.Path.home() / ".local/state/niri-ws_follow.lock"
DEBOUNCE_S = 0.25
BOOTSTRAP_S = 2.0


def acquire_lock():
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    f = open(LOCK, "w")
    try:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("ws_follow: another instance is running, exiting", file=sys.stderr)
        sys.exit(0)
    f.write(f"{os.getpid()}\n")
    f.flush()
    return f  # keep fd alive for process lifetime


def load_rules():
    """Return [(compiled_app_id_regex, workspace_name)] from config.kdl."""
    try:
        text = CFG.read_text()
    except OSError:
        return []
    rules = []
    for m in re.finditer(r"window-rule\s*\{(.*?)\}", text, re.S):
        block = m.group(1)
        ws = re.search(r'open-on-workspace\s+"([^"]+)"', block)
        if not ws:
            continue
        rm = re.search(r'app-id=r#"(.+?)"#', block)
        if rm:
            rules.append((re.compile(rm.group(1)), ws.group(1)))
            continue
        qm = re.search(r'app-id="((?:[^"\\]|\\.)*)"', block)
        if qm:
            rules.append((re.compile(re.escape(qm.group(1))), ws.group(1)))
    return rules


def main():
    acquire_lock()
    rules_box = [load_rules()]
    try:
        rules_mtime = CFG.stat().st_mtime
    except OSError:
        rules_mtime = None
    state = {}    # id -> (app_id, ws)
    timers = {}   # id -> Timer
    t0 = time.monotonic()

    def match_ws(app_id):
        if not app_id:
            return None
        for rx, ws in rules_box[0]:
            if rx.search(app_id):
                return ws
        return None

    def act(wid):
        e = state.get(wid)
        if not e:
            return
        app_id, ws = e
        if match_ws(app_id) is None:
            return  # not rule-pinned; never follow
        # Pinned app: follow the window to whatever workspace it's on now.
        # Covers "newly opened" (the rule already placed it on its workspace)
        # and "moved" (Mod+Shift+N sent it elsewhere).
        try:
            subprocess.run(
                ["niri", "msg", "action", "focus-workspace", str(ws)],
                timeout=3, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (subprocess.SubprocessError, OSError):
            pass

    def schedule(wid):
        old = timers.pop(wid, None)
        if old:
            old.cancel()
        t = threading.Timer(DEBOUNCE_S, act, args=(wid,))
        timers[wid] = t
        t.daemon = True
        t.start()

    def read_events():
        nonlocal rules_mtime
        failures = 0
        while True:
            proc = subprocess.Popen(
                ["niri", "msg", "--json", "event-stream"],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            try:
                for line in proc.stdout:
                    failures = 0  # any event means niri is alive
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        d = json.loads(line)
                    except ValueError:
                        continue
                    windows = []
                    if "WindowsChanged" in d:
                        windows = d["WindowsChanged"].get("windows", [])
                    if "WindowOpenedOrChanged" in d:
                        w = d["WindowOpenedOrChanged"].get("window")
                        if w:
                            windows.append(w)
                    if not windows:
                        continue
                    now = time.monotonic()
                    if rules_mtime != (CFG.stat().st_mtime if CFG.exists() else None):
                        rules_box[0] = load_rules()
                        try:
                            rules_mtime = CFG.stat().st_mtime
                        except OSError:
                            pass
                    for w in windows:
                        wid = w.get("id")
                        app_id = w.get("app_id")
                        ws = w.get("workspace_id")
                        if wid is None or ws is None:
                            continue
                        prev = state.get(wid)
                        if prev is None:
                            state[wid] = (app_id, ws)
                            if now - t0 >= BOOTSTRAP_S:
                                schedule(wid)  # freshly opened window
                        elif prev != (app_id, ws):
                            state[wid] = (app_id, ws)
                            schedule(wid)  # moved -> follow
            finally:
                proc.kill()
            # A full stream cycle that produced no windows event at all.
            # (A live niri constantly emits WorkspacesChanged/WindowsChanged.)
            failures += 1
            if failures >= 3:
                # Stream kept dying without events: niri is gone (session
                # ended). Exit so the flock releases for next login's
                # spawn-at-startup instance.
                print("ws_follow: niri appears to be gone, exiting", file=sys.stderr)
                return
            time.sleep(1)

    read_events()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ws_follow fatal: {exc!r}", file=sys.stderr)
        sys.exit(1)

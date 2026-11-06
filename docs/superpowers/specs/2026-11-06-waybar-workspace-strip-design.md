# Waybar workspace strip — design

Date: 2026-11-06
Status: approved (approach C: patched local waybar)

## Goal

Add a second workspace widget that renders, per workspace, an embossed numbered
tile carrying the real application icons of the windows on that workspace.
It sits in the bar's centre group immediately before the clock. The existing
`niri/workspaces` dots in `modules-left` stay untouched.

## Why a patched waybar

Stock waybar 0.15 renders text/markup only — no module can draw images, and a
label is a single click target. Real app artwork plus per-tile clicks therefore
requires either a second layer-shell program (rejected: z-order against the
bar's 70 % black surface, positioning math against the clock, fullscreen
behaviour) or a native module. Native wins because the strip is then literally
part of the bar: layout, clicks, theming, and fullscreen handling are waybar's.

## Constraints and facts

- Fork lives at `~/dev/tools/waybar` (upstream `1687ec7` + ampere commits).
- `src/modules/niri/backend.cpp` already provides the niri IPC event stream
  (`EventStream`, `WorkspacesChanged`, `WorkspaceActivated`, reconnect loop),
  so the new module only subscribes.
- niri window JSON: `app_id`, `workspace_id`, `is_focused`, `id`.
- App icons resolve via `Gio::DesktopAppInfo` → `Gio::ThemedIcon` →
  `Gtk::IconTheme`; verified for `brave-browser`, `floorp`, `thunar`, `zcode`.
- Bar height 32 px; output logical 2880×1620 @ scale 1.333.

## Behaviour

- Tiles rendered for workspaces that hold ≥ 1 window, plus the active
  workspace. Empty non-active workspaces are not rendered (matches the
  dynamic behaviour of the existing dots).
- Each tile: embossed background, workspace index, then one icon per distinct
  app on that workspace, de-duplicated, ordered by first appearance.
- Active workspace: brighter tile plus accent ring.
- Left click anywhere on a tile: focus that workspace
  (`niri msg action focus-workspace <idx>`).
- App icons are indicators; clicking them does nothing extra.

## Visual

Emboss comes from CSS, not drawing code: vertical `linear-gradient`,
`box-shadow: inset` for the top highlight and bottom shadow, 6 px radius,
bold white index, 16 px icons. Palette follows the reference (deep blue-grey,
brighter active tile); all values live in one block of `style.css` so they can
be retuned without touching C++.

## Architecture

```
niri/backend.cpp  ──(gIPC event stream)──►  WorkspaceStrip::onEvent
                                                  │
                                    signature compare (ws ids + app_ids + active)
                                                  │
                             rebuild tiles only when the signature changes
                                                  │
                     Gtk::Button{ Gtk::Box{ Gtk::Label(idx), Gtk::Image × n } }
```

- No polling: updates are driven by IPC events, with waybar's existing
  reconnect-on-drop behaviour.
- Rebuilds are signature-gated so title-change events (which fire constantly)
  do not cause widget churn.

## Files

| File | Change |
|---|---|
| `src/modules/niri/workspace_strip.cpp` | new module (~400–500 lines) |
| `include/modules/niri/workspace_strip.hpp` | new header |
| `src/factory.cpp` | register `niri/workspace-strip` |
| `meson.build` | add source |
| `~/.config/waybar/config` | `niri/workspace-strip` in `modules-center` before `clock` |
| `~/.config/waybar/style.css` | tile/emboss/active styling |
| `~/.config/niri/config.kdl` | spawn the fork binary by explicit path |
| repo `install.sh` | clone upstream at pinned rev, apply `patches/*.patch`, build, install |
| repo `patches/waybar-workspace-strip.patch` | the patch itself |

## Config surface (minimal)

```json
"niri/workspace-strip": {
  "icon-size": 16,
  "tooltip": false
}
```

No format string in v1 — the tile layout is fixed (index + icons). Add knobs
only if the look needs tuning later.

## Failure modes

- niri IPC unavailable: module logs and stays empty (no crash); waybar keeps
  running the rest of the bar.
- Unresolvable app: falls back to the app_id as an icon name, then to no icon.
- Stock waybar running the patched config: unknown module is skipped with a
  warning; the rest of the bar is unaffected.

## Testing

1. Build cleanly; `waybar --version` reports the fork.
2. Open/close windows on several workspaces; icons appear/disappear without
   flicker, tiles appear only for populated + active workspaces.
3. Click each tile; workspace switches.
4. Switch workspaces; active tile styling moves.
5. Kill the niri IPC socket mid-run; module recovers on reconnect.
6. Pixel-scan a screenshot to confirm tile geometry sits immediately left of
   the clock with no overlap.

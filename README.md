# dotfiles — niri + waybar + configs

Reproducible setup for a niri wayland session with a customized waybar:
live system stats (CPU/MEM/temps), network arrows, Bluetooth device
batteries, blue-light toggle, floating keybinding cheat-sheet window,
power menu, app switching, and more.

## Quick start

```sh
git clone https://github.com/kknixx/dotfiles
cd dotfiles
./install.sh            # deps + configs + tools + wallpaper (waybar from your distro's repos)
# ./install.sh --gtk    # also install GTK settings (Espectro/Pop theme refs)
```

Then choose the **Niri** session at your login manager.

### Options

| flag         | effect                                          |
|--------------|-------------------------------------------------|
| `--gtk`      | also copy `~/.config/gtk-3.0` / `gtk-4.0`       |
| `--no-deps`  | skip system package install (you handle deps)   |
| `--home DIR` | install into DIR instead of `$HOME` (testing)   |

## What gets installed

- **niri** (scrollable-tiling Wayland compositor)
- **waybar** — the official distro package (0.15+; needs the `niri/workspaces`
  module). No fork, no build step.
- **configs** → `~/.config/{waybar,niri,foot,ghostty,sunsetr}` (existing files
  are backed up to `*.pre-install.<date>`)
- **sunsetr** (blue-light filter, installed via cargo on all distros) + the
  waybar `bluelight` toggle module that starts/stops it
  (`~/.config/sunsetr/`)
- **tools** → `~/.local/bin/` (`dfr-launch-or-focus-tui`, `dfr-tz-set`)
- **wallpaper** → `~/Pictures/`

## Distro support

`install.sh` detects pacman / dnf / yum / apt / zypper / brew.

- **Arch**: everything bar a few extras is in the official repos; the rest
  (`elephant-bin`, `elephant-niriactions-bin`, `bluetui`, `impala`, `monitor`,
  `lxpolkit`) come from AUR via `yay`/`paru` if present.
- **Everywhere**: niri and sunsetr are not in the official repos (niri may be
  packaged on some), so both fall back to cargo. niri must build from git
  (`cargo install --git https://github.com/YaLTeR/niri`) — do **not**
  `cargo install niri`, the crates.io name is a squatted placeholder. sunsetr
  is a normal crate: `cargo install sunsetr`.

## Dependencies (manual list, for `--no-deps`)

Core: `niri foot ghostty wofi nwg-dock grim slurp wl-clipboard swaylock
imagemagick brightnessctl jq curl playerctl mpd mpd-mpris dunst swaybg
gnome-keyring bluez networkmanager waybar` (waybar 0.15+ from your distro)

Bar font: `ttf-cascadia-mono-nerd` (CaskaydiaMono Nerd Font)

AUR extras: `elephant-bin elephant-niriactions-bin bluetui impala monitor lxpolkit`

## Notes

- The GTK settings (`--gtk`) reference the **Espectro** GTK3 theme and **Pop**
  icon theme, which are not vendored (large theme trees, distro-specific).
  Install them separately or GTK falls back to defaults.
- The bar's custom `help` launcher shows the keybinding cheat-sheet in a
  floating window (ESC quits).
- `config/niri/config.kdl` contains a few absolute `/home/<user>` paths;
  `install.sh` rewrites them to your `$HOME` at install time.
- Output name `HDMI-A-2` and scale `1.333` in `config.kdl` are specific to the
  source machine's monitor — adjust for your display if needed.

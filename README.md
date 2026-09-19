# dotfiles — niri + waybar (ampere fork) + configs

Reproducible setup for a niri wayland session with a customized waybar:
live system stats (CPU/MEM/temps), network arrows, floating keybinding
cheat-sheet window, power menu, app switching, and more.

## Quick start

```sh
git clone https://github.com/kknixx/dotfiles
cd dotfiles
./install.sh            # deps + build waybar fork + configs + tools + wallpaper
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
- **waybar** — built from the vendored fork in `waybar-fork/` (a fork of
  [Alexays/Waybar](https://github.com/Alexays/Waybar) at `1687ec7` with 12 local
  commits, including the GPU **ampere** module and the custom module tweaks this
  config relies on). Installed to `~/.local/bin/waybar`.
- **configs** → `~/.config/{waybar,niri,foot}` (existing files are backed up to
  `*.pre-install.<date>`)
- **tools** → `~/.local/bin/` (`dfr-launch-or-focus-tui`, `dfr-tz-set`)
- **wallpaper** → `~/.config/foot`, `~/Pictures/`

## Distro support

`install.sh` detects pacman / dnf / yum / apt / zypper / brew.

- **Arch**: everything bar a few extras is in the official repos; the rest
  (`elephant-bin`, `elephant-niriactions-bin`, `bluetui`, `impala`, `monitor`,
  `lxpolkit`) come from AUR via `yay`/`paru` if present.
- **Other distros**: niri falls back to building from source
  (`cargo install --git https://github.com/YaLTeR/niri`) if your distro doesn't
  package it. (Do **not** `cargo install niri` — the crates.io name is a
  squatted placeholder.)

## Dependencies (manual list, for `--no-deps`)

Core: `niri foot ghostty wofi nwg-dock grim slurp wl-clipboard swaylock
imagemagick brightnessctl jq curl playerctl mpd mpd-mpris dunst swaybg
gnome-keyring bluez networkmanager`

Bar font: `ttf-cascadia-mono-nerd` (CaskaydiaMono Nerd Font)

Waybar build (meson + ninja + dev libs): `gtkmm3 gtk-layer-shell libpipewire
playerctl mpd libmpdclient libnl libevdev libinput libjack wireplumber upower
fmt spdlog libsystemd dbusmenu-gtk libpulse libmm-glib jsoncpp glib2`

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

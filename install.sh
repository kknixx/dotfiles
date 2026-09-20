#!/usr/bin/env bash
#
# install.sh — sets up niri + the waybar fork + all configs from this repo.
#
# Usage:
#   ./install.sh              # full install (deps, waybar fork, configs, tools, wallpaper)
#   ./install.sh --gtk        # also install the GTK settings (Espectro/Pop theme refs)
#   ./install.sh --no-deps    # skip system package install (you handle deps)
#   ./install.sh --home DIR   # install into DIR instead of $HOME (testing)
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_HOME="${HOME}"
INSTALL_GTK=0
INSTALL_DEPS=1

while [ $# -gt 0 ]; do
  case "$1" in
    --gtk)      INSTALL_GTK=1 ;;
    --no-deps)  INSTALL_DEPS=0 ;;
    --home)     shift; TARGET_HOME="${1:---home needs a path}" ;;
    --help|-h)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
  shift
done

log()  { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null || die "git is required"

# ---------------------------------------------------------------- package mgr
detect_pkg() {
  if   command -v pacman; then PKG=pacman
  elif command -v dnf;    then PKG=dnf
  elif command -v yum;    then PKG=yum
  elif command -v apt-get; then PKG=apt
  elif command -v zypper; then PKG=zypper
  elif command -v brew;   then PKG=brew
  else PKG=""
  fi
}

# run the package installer with a list; returns 0/1, never fatal here
pkg_install() {
  local pkgs=("$@")
  [ "${#pkgs[@]}" -eq 0 ] && return 0
  case "$PKG" in
    pacman)  pacman --noconfirm -S --needed "${pkgs[@]}" ;;
    dnf|yum) sudo dnf install -y "${pkgs[@]}" ;;
    apt)     sudo apt-get update -qq && sudo apt-get install -y "${pkgs[@]}" ;;
    zypper)  sudo zypper --non-interactive install "${pkgs[@]}" ;;
    brew)    brew install "${pkgs[@]}" ;;
    *) warn "no package manager found; install manually: ${pkgs[*]}"; return 1 ;;
  esac
}

# AUR helper (Arch only, needs yay/paru)
aur_install() {
  local helper=""
  command -v yay  && helper=yay
  command -v paru && helper=paru
  if [ -z "$helper" ]; then
    warn "yay/paru not found; skipping AUR extras: $*"
    return 0
  fi
  $helper --noconfirm -S --needed "$@"
}

# ------------------------------------------------------------------- 1. deps
if [ "$INSTALL_DEPS" -eq 1 ]; then
  log "1/6 Detecting distro and installing system dependencies"
  detect_pkg
  [ -n "$PKG" ] || warn "no known package manager detected — continuing with build/install only"

  case "$PKG" in
    pacman)
      # niri 26.x is in the official repos, as is the bar/lock/screenshot/app stack
      pkg_install niri foot ghostty wofi nwg-dock grim slurp wl-clipboard swaylock \
        imagemagick brightnessctl jq curl playerctl mpd mpd-mpris \
        libmpdclient bluez networkmanager ttf-cascadia-mono-nerd \
        dunst swaybg gnome-keyring
      # AUR-only extras: app switcher TUIs, niri actions provider, polkit agent
      # (No waybar package here — we build the vendored fork ourselves in step 2.)
      aur_install elephant-bin elephant-niriactions-bin bluetui impala monitor lxpolkit
      ;;
    dnf|yum)
      pkg_install niri foot wofi nwg-dock grim slurp wl-clipboard swaylock \
        ImageMagick brightnessctl jq curl mpd mpd-mpris dbusmenu-gtk3 \
        dunst swaybg gnome-keyring ttf-cascadia \
        glib2-devel gtkmm3-devel gtk-layer-shell-devel libpipewire-devel \
        playerctl libnl3-devel jsoncpp-devel libevdev-devel libinput-devel \
        jack2-devel wireplumber-devel upower-devel fmt-devel spdlog-devel \
        systemd-devel libmpdclient-devel
      warn "AUR-only extras (elephant, bluetui, impala, monitor, lxpolkit) have no dnf build yet — see README"
      ;;
    apt)
      pkg_install niri foot ghostty wofi nwg-dock grim slurp wl-clipboard swaylock \
        imagemagick brightnessctl jq curl playerctl mpd mpd-mpris \
        dunst swaybg gnome-keyring \
        libgtkmm-3.0-dev libgtk-layer-shell-dev libpipewire-0.3-dev \
        libjsoncpp-dev libnl-3-dev libnl-genl-3-dev libevdev-dev libinput-dev \
        libjack-jackd2-dev libwireplumber-0.5-dev libupower-glib-dev \
        libfmt-dev libspdlog-dev libsystemd-dev libmpdclient-dev libdbusmenu-gtk3-dev
      warn "niri may not be packaged on your release yet — the cargo fallback below covers it"
      warn "lxpolkit (polkit agent) is AUR/Flathub-only; install or skip"
      ;;
    *)
      warn "package map not implemented for '$PKG' — see README for the dependency list"
      ;;
  esac

  # Distros without niri packaged: build from source (needs rust).
  # NOTE: do NOT `cargo install niri` — the crates.io "niri" name is a squatted
  # placeholder (0.0.0), not the compositor. Build from the git repo instead.
  if ! command -v niri >/dev/null; then
    if command -v cargo >/dev/null; then
      log "niri not packaged here — building from source via cargo (this takes a while)"
      cargo install --locked --git https://github.com/YaLTeR/niri
    else
      warn "niri is not installed and no rust toolchain found."
      warn "Install rust (https://rustup.rs) then run: cargo install --git https://github.com/YaLTeR/niri"
      warn "Or install niri from your distro's packages (Arch: 'pacman -S niri')."
    fi
  fi

  # sunsetr (blue-light filter, waybar bluelight module): not packaged in any
  # official repo, so build from crates.io on every distro (a normal crate,
  # unlike niri — `cargo install sunsetr` is safe).
  if ! command -v sunsetr >/dev/null; then
    if command -v cargo >/dev/null; then
      log "sunsetr not packaged here — building from crates.io via cargo"
      cargo install --locked sunsetr
    else
      warn "sunsetr not found and no rust toolchain — the waybar bluelight module will be inert."
    fi
  fi
else
  log "1/6 Dependencies (skipped via --no-deps)"
fi

# ---------------------------------------------------------------- 2. waybar
log "2/6 Building the waybar fork (vendored in waybar-fork/)"

build_waybar_deps() {
  case "$PKG" in
    pacman)
      pkg_install base-devel meson ninja glib2 gtkmm3 gtk-layer-shell \
        libpipewire playerctl mpd libmpdclient libnl jsoncpp libevdev \
        libinput libjack wireplumber upower fmt spdlog libsystemd \
        dbusmenu-gtk libpulse libmm-glib
      ;;
    dnf|yum)
      sudo dnf install -y base-devel meson ninja gtkmm3-devel gtk-layer-shell-devel \
        libpipewire-devel jsoncpp-devel libnl3-devel libevdev-devel libinput-devel \
        jack2-devel wireplumber-devel upower-devel fmt-devel spdlog-devel \
        systemd-devel mpd-devel libmpdclient-devel dbusmenu-gtk3-devel
      ;;
    apt)
      sudo apt-get install -y build-essential meson ninja-build g++ \
        libglib2.0-dev libgtkmm-3.0-dev libgtk-layer-shell-dev libpipewire-0.3-dev \
        libjsoncpp-dev libnl-3-dev libnl-genl-3-dev libevdev-dev libinput-dev \
        libjack-jackd2-dev libwireplumber-0.5-dev libupower-glib-dev \
        libfmt-dev libspdlog-dev libsystemd-dev libmpdclient-dev libdbusmenu-gtk3-dev
      ;;
    *) warn "install waybar build deps manually (meson, ninja, gtkmm3, gtk-layer-shell, libpipewire, jsoncpp, libnl, libevdev, libinput, libjack, wireplumber, upower, fmt, spdlog, libsystemd, libmpdclient, dbusmenu-gtk3)" ;;
  esac
}
[ "$INSTALL_DEPS" -eq 1 ] && build_waybar_deps || true

SRC_DIR="$REPO_DIR/waybar-fork"
[ -f "$SRC_DIR/meson.build" ] || die "waybar-fork/meson.build not found — is the repo complete?"

# Build in a scratch copy so the repo tree stays clean.
# Optional, hard-to-satisfy features auto-disable if their libs are missing,
# but force the ones we do not ship so the build is deterministic.
BUILD_ROOT="$(mktemp -d)"
trap 'rm -rf "$BUILD_ROOT"' EXIT
BUILD_DIR="$BUILD_ROOT/build"
cp -a "$SRC_DIR" "$BUILD_ROOT/src"
meson setup -Dtests=disabled -Dman-pages=disabled -Dcava=disabled -Dgps=disabled \
  -Dwwan=disabled -Dlogin-proxy=disabled -Dsndio=disabled -Drfkill=disabled \
  "$BUILD_ROOT/src" "$BUILD_DIR"
meson compile -C "$BUILD_DIR"
install -Dm755 "$BUILD_DIR/waybar" "$TARGET_HOME/.local/bin/waybar"

# ------------------------------------------------------------- 3. waybar cfg
install_config_dir() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  if [ -d "$dst" ] && [ -n "$(ls -A "$dst" 2>/dev/null)" ]; then
    local stamp; stamp="$(date +%Y%m%d)"
    for f in "$dst"/*; do
      [ -f "$f" ] && cp -a "$f" "$f.pre-install.$stamp"
    done
    warn "backed up existing $dst files to *.pre-install.$stamp"
  fi
  cp -a "$src"/. "$dst"/
}

log "3/6 Installing configs"
install_config_dir "$REPO_DIR/config/waybar"  "$TARGET_HOME/.config/waybar"
install_config_dir "$REPO_DIR/config/niri"    "$TARGET_HOME/.config/niri"
install_config_dir "$REPO_DIR/config/foot"    "$TARGET_HOME/.config/foot"
install_config_dir "$REPO_DIR/config/ghostty" "$TARGET_HOME/.config/ghostty"
install_config_dir "$REPO_DIR/config/sunsetr"  "$TARGET_HOME/.config/sunsetr"

# Rewrite the absolute /home/kk paths baked into config.kdl to this user's $HOME
KDL="$TARGET_HOME/.config/niri/config.kdl"
sed -i "s|/home/kk|$TARGET_HOME|g" "$KDL"

chmod +x "$TARGET_HOME/.config/waybar/power-menu.sh" \
         "$TARGET_HOME/.config/waybar/scripts/"*.sh \
         "$TARGET_HOME/.config/niri/"*.sh \
         "$TARGET_HOME/.config/niri/keybinds-help.py" 2>/dev/null || true

# ---------------------------------------------------------------- 4. tools
log "4/6 Installing helper tools"
mkdir -p "$TARGET_HOME/.local/bin"
for t in "$REPO_DIR"/tools/*; do
  install -m755 "$t" "$TARGET_HOME/.local/bin/$(basename "$t")"
done

# ----------------------------------------------------------------- 5. wallpaper
log "5/6 Installing wallpaper"
mkdir -p "$TARGET_HOME/Pictures"
cp -a "$REPO_DIR"/wallpaper/* "$TARGET_HOME/Pictures/" 2>/dev/null || \
  warn "no wallpaper files found in repo"

# --------------------------------------------------------------- 6. gtk/verify
if [ "$INSTALL_GTK" -eq 1 ]; then
  log "6/6 Installing GTK settings (--gtk)"
  install_config_dir "$REPO_DIR/config/gtk-3.0" "$TARGET_HOME/.config/gtk-3.0"
  install_config_dir "$REPO_DIR/config/gtk-4.0" "$TARGET_HOME/.config/gtk-4.0"
  warn "settings.ini references the 'Espectro' GTK3 theme and 'Pop' icon theme, which are"
  warn "not vendored here (theme trees are large / distro-specific). Install them separately,"
  warn "or GTK falls back to defaults. (gtk-4.0 assets on the source box symlink the"
  warn "Orchis theme and are therefore not copied.)"
fi

log "Verifying"
command -v niri && niri --version 2>/dev/null | head -1 || warn "niri not on PATH (check cargo/bin or your distro bin)"
"$TARGET_HOME/.local/bin/waybar" --version 2>/dev/null | head -1 || true
echo "Installed:"
find "$TARGET_HOME/.config/waybar" "$TARGET_HOME/.config/niri" \
     "$TARGET_HOME/.config/foot" "$TARGET_HOME/.config/ghostty" \
  -type f 2>/dev/null | sed "s|$TARGET_HOME|~|" | sort
for t in "$TARGET_HOME"/.local/bin/*; do [ -f "$t" ] && echo "~/.local/bin/$(basename "$t")"; done

# Wayland session entry (needed when niri came from cargo, not a distro package)
if [ ! -f /usr/share/wayland-sessions/niri.desktop ] && command -v niri-session >/dev/null; then
  mkdir -p "$TARGET_HOME/.local/share/wayland-sessions"
  cat > "$TARGET_HOME/.local/share/wayland-sessions/niri.desktop" <<EOF
[Desktop Entry]
Name=Niri
Comment=Scrollable-tiling Wayland compositor
Exec=$(command -v niri-session)
Type=Application
EOF
  echo "wrote ~/.local/share/wayland-sessions/niri.desktop"
fi

log "Done"
echo "Next: select the 'Niri' session at your login manager and log in."
echo "The bar (waybar) starts automatically via niri's spawn-at-startup."

#!/usr/bin/env bash
# Apollo — KWin + Quickshell fresh Arch TTY installer
# Usage (normal user with sudo):
#   git clone https://github.com/kinplus127/Apollo.git ~/Apollo && cd ~/Apollo && ./install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="[apollo]"

info()  { printf '%s %s\n' "$LOG_PREFIX" "$*"; }
warn()  { printf '%s warning: %s\n' "$LOG_PREFIX" "$*" >&2; }
die()   { printf '%s error: %s\n' "$LOG_PREFIX" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

if [[ ${EUID:-0} -eq 0 ]]; then
  die "run as a normal user (script will call sudo). do not run as root."
fi

need_cmd sudo
need_cmd pacman
need_cmd install

if [[ ! -f /etc/arch-release ]]; then
  die "this installer targets Arch Linux (/etc/arch-release not found)"
fi

if ! sudo -n true 2>/dev/null; then
  info "sudo password may be required"
fi

INSTALL_USER="${SUDO_USER:-$USER}"
if [[ "$INSTALL_USER" == root ]] || [[ -z "$INSTALL_USER" ]]; then
  INSTALL_USER="$(id -un)"
fi

# --- packages ---
PACMAN_PKGS=(
  kwin
  breeze
  kglobalaccel
  kglobalacceld
  kscreenlocker
  xdg-desktop-portal
  xdg-desktop-portal-kde
  polkit-kde-agent
  qt6-wayland
  qt6-declarative
  qt6-svg
  qt6-multimedia
  qt6-5compat
  pipewire
  wireplumber
  greetd
  # NVIDIA: open kernel modules + userspace; VA-API via libva-nvidia-driver.
  # nvidia-utils already pulls egl-wayland / egl-gbm / libglvnd; Arch enables modeset.
  nvidia-open
  nvidia-utils
  libva-nvidia-driver
  fish
  kitty
  yazi
  neovim
  # LazyVim / editor helpers
  ripgrep
  fd
  fzf
  unzip
  wl-clipboard
  libnotify
  networkmanager
  bluez
  bluez-utils
  base-devel
  git
)

info "installing official packages..."
sudo pacman -Syu --needed --noconfirm "${PACMAN_PKGS[@]}"

# Drop greeters / display managers we do not want
if pacman -Q greetd-tuigreet >/dev/null 2>&1; then
  info "removing greetd-tuigreet..."
  sudo pacman -Rns --noconfirm greetd-tuigreet || warn "could not remove greetd-tuigreet"
fi
if systemctl list-unit-files sddm.service >/dev/null 2>&1; then
  sudo systemctl disable sddm.service 2>/dev/null || true
  info "disabled sddm.service"
fi

# NVIDIA modeset: shipped by Arch nvidia-utils (no extra modprobe/mkinitcpio here).

# --- fish as login shell for this account ---
FISH_BIN="$(command -v fish)"
if [[ -n "$FISH_BIN" ]]; then
  if ! grep -qxF "$FISH_BIN" /etc/shells 2>/dev/null; then
    info "adding $FISH_BIN to /etc/shells"
    echo "$FISH_BIN" | sudo tee -a /etc/shells >/dev/null
  fi
  CURRENT_SHELL="$(getent passwd "$INSTALL_USER" | cut -d: -f7 || true)"
  if [[ "$CURRENT_SHELL" != "$FISH_BIN" ]]; then
    info "setting login shell for $INSTALL_USER → $FISH_BIN"
    sudo chsh -s "$FISH_BIN" "$INSTALL_USER"
  else
    info "login shell already fish for $INSTALL_USER"
  fi
else
  warn "fish binary not found after install"
fi

# --- AUR helper (yay) ---
install_yay() {
  if command -v yay >/dev/null 2>&1; then
    info "yay already installed"
    return
  fi
  info "installing yay (AUR helper)..."
  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  git clone --depth=1 https://aur.archlinux.org/yay.git "$tmp/yay"
  (cd "$tmp/yay" && makepkg -si --noconfirm)
}

install_yay

info "installing quickshell from AUR..."
yay -S --needed --noconfirm quickshell

info "installing brave-origin-bin (official Brave) from AUR..."
yay -S --needed --noconfirm brave-origin-bin

# --- install session files (Apollo brand) ---
SHARE_DIR=/usr/local/share/apollo
BIN_WRAPPER=/usr/local/bin/apollo-session
DESKTOP_DST=/usr/local/share/wayland-sessions/apollo.desktop

info "installing session scripts to $SHARE_DIR ..."
sudo mkdir -p "$SHARE_DIR/scripts" /usr/local/share/wayland-sessions /usr/local/bin
sudo install -m 0755 "$ROOT/scripts/start-apollo.sh" "$SHARE_DIR/scripts/start-apollo.sh"
sudo install -m 0755 "$ROOT/scripts/apollo-session" "$BIN_WRAPPER"
sudo install -m 0644 "$ROOT/session/apollo.desktop" "$DESKTOP_DST"

# Remove old Universe-branded session if present
sudo rm -f /usr/local/bin/universe-kwin-session \
  /usr/local/share/wayland-sessions/universe-kwin.desktop
sudo rm -rf /usr/local/share/universe-kwin

# --- greetd: no greeter UI, autologin this account into Apollo ---
info "configuring greetd autologin for $INSTALL_USER (no tuigreet)..."
sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<GREETD
[terminal]
vt = 1

# Boot straight into Apollo as ${INSTALL_USER} — no greeter.
[initial_session]
command = "apollo-session"
user = "${INSTALL_USER}"

# After logout / session exit, start Apollo again (still no greeter).
[default_session]
command = "apollo-session"
user = "${INSTALL_USER}"
GREETD



# --- LazyVim (Neovim distro) ---
NVIM_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
if [[ ! -e "$NVIM_CFG" ]]; then
  info "installing LazyVim starter → $NVIM_CFG"
  git clone --depth=1 https://github.com/LazyVim/starter "$NVIM_CFG"
  rm -rf "$NVIM_CFG/.git"
else
  info "keep existing $NVIM_CFG (not overwriting LazyVim/neovim config)"
fi


# --- global shortcuts (Super+Q close, Super+T kitty) ---
KGSRC="${XDG_CONFIG_HOME:-$HOME/.config}/kglobalshortcutsrc"
KGSNIP="$ROOT/config/kglobalshortcutsrc.snippet"
if [[ -f "$KGSNIP" ]]; then
  mkdir -p "$(dirname "$KGSRC")"
  if [[ ! -f "$KGSRC" ]]; then
    install -m 0644 "$KGSNIP" "$KGSRC"
    info "wrote $KGSRC (Meta+Q close, Meta+T kitty, Meta+Shift+T tiles)"
  else
    # idempotent-ish: ensure our bindings exist / override conflicting Meta+T tiles
    if ! grep -q '^Window Close=Meta+Q' "$KGSRC" 2>/dev/null; then
      if grep -q '^Window Close=' "$KGSRC"; then
        sed -i 's/^Window Close=.*/Window Close=Meta+Q\\tAlt+F4,Alt+F4,Close Window/' "$KGSRC"
      else
        printf '\n[kwin]\nWindow Close=Meta+Q\\tAlt+F4,Alt+F4,Close Window\n' >> "$KGSRC"
      fi
    fi
    if grep -q '^Edit Tiles=' "$KGSRC"; then
      sed -i 's/^Edit Tiles=.*/Edit Tiles=Meta+Shift+T,Meta+T,Toggle Tiling/' "$KGSRC"
    fi
    if ! grep -q '\[services\]\[kitty.desktop\]' "$KGSRC"; then
      printf '\n[services][kitty.desktop]\n_k_friendly_name=kitty\n_launch=Meta+T,none,Launch kitty\n' >> "$KGSRC"
    else
      sed -i '/\[services\]\[kitty.desktop\]/,/^\[/{s/^_launch=.*/_launch=Meta+T,none,Launch kitty/;}' "$KGSRC" || true
    fi
    info "updated shortcuts in $KGSRC"
  fi
fi

# --- wallpapers (pixel-perfect copy, no recompress) ---
WP_SRC="$ROOT/wallpapers"
WP_DST="${XDG_PICTURES_DIR:-$HOME/Pictures}/wallpapers"
if [[ -d "$WP_SRC" ]]; then
  info "installing wallpapers → $WP_DST (exact copy)"
  mkdir -p "$WP_DST"
  # -p preserve mode/times; no convert/resize
  find "$WP_SRC" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0 |
    while IFS= read -r -d '' f; do
      install -m 0644 "$f" "$WP_DST/$(basename "$f")"
    done
else
  warn "no wallpapers/ directory in repo"
fi

# --- user config (idempotent) ---
QS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/apollo"
mkdir -p "$QS_DIR"
if [[ ! -f "$QS_DIR/shell.qml" ]]; then
  OLD_QS="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/universe/shell.qml"
  if [[ -f "$OLD_QS" ]]; then
    install -m 0644 "$OLD_QS" "$QS_DIR/shell.qml"
    info "migrated Quickshell config from universe → apollo"
  else
    install -m 0644 "$ROOT/config/quickshell/shell.qml" "$QS_DIR/shell.qml"
    info "wrote $QS_DIR/shell.qml"
  fi
else
  info "keep existing $QS_DIR/shell.qml"
fi

KWINRC="${XDG_CONFIG_HOME:-$HOME/.config}/kwinrc"
mkdir -p "$(dirname "$KWINRC")"
if [[ ! -f "$KWINRC" ]]; then
  install -m 0644 "$ROOT/config/kwin/kwinrc.snippet" "$KWINRC"
  info "wrote $KWINRC"
else
  info "keep existing $KWINRC (not overwriting)"
fi

# --- services ---
info "enabling NetworkManager, bluetooth, greetd..."
sudo systemctl enable NetworkManager.service || warn "could not enable NetworkManager"
sudo systemctl enable bluetooth.service || warn "could not enable bluetooth"
sudo systemctl enable greetd.service

cat <<DONE

============================================================
Apollo install finished.

Installed / configured:
  - Apollo DE: KWin + Breeze + Quickshell (no plasmashell)
  - NVIDIA: nvidia-open + nvidia-utils + libva-nvidia-driver
  - greetd autologin as ${INSTALL_USER} (NO greeter / NO tuigreet / NO SDDM)
  - fish as login shell for ${INSTALL_USER}
  - kitty, yazi, neovim + LazyVim starter
  - NetworkManager + BlueZ

Next:
  1) reboot → should land in Apollo automatically
  2) wallpapers: ~/Pictures/wallpapers/
  3) edit shell:  ~/.config/quickshell/apollo/shell.qml
  4) edit kwin:   ~/.config/kwinrc

NVIDIA:
  - modeset comes from Arch's nvidia-utils; egl-wayland is a dep of nvidia-utils

apollod:
  - Planned Go daemon for your unified settings center
    (Wi-Fi, Bluetooth, monitors, Quickshell look/feel, keybinds, exec).
  - Not installed yet; start-apollo.sh launches it when on PATH.

Re-run safely: ./install.sh  (existing user configs are kept)
============================================================
DONE

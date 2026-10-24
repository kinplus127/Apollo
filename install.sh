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
  greetd-tuigreet
  nvidia
  nvidia-utils
  egl-wayland
  libglvnd
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

if systemctl list-unit-files sddm.service >/dev/null 2>&1; then
  sudo systemctl disable sddm.service 2>/dev/null || true
  info "disabled sddm.service (using greetd + tuigreet instead)"
fi

# --- NVIDIA modesetting ---
info "configuring NVIDIA DRM modeset..."
sudo tee /etc/modprobe.d/nvidia.conf >/dev/null <<'NVIDIA'
options nvidia_drm modeset=1
options nvidia_drm fbdev=1
NVIDIA

if [[ -f /etc/mkinitcpio.conf ]]; then
  if ! grep -qE '(^| )nvidia( |$)' /etc/mkinitcpio.conf; then
    if grep -q '^MODULES=' /etc/mkinitcpio.conf; then
      sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
      sudo sed -i 's/MODULES=(  */MODULES=(/; s/  )/)/' /etc/mkinitcpio.conf
      info "updated MODULES in /etc/mkinitcpio.conf — rebuilding initramfs..."
      sudo mkinitcpio -P || warn "mkinitcpio failed; reboot may still work if modules load later"
    fi
  else
    info "nvidia modules already referenced in mkinitcpio.conf"
  fi
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

# --- greetd + tuigreet ---
info "configuring greetd + tuigreet..."
sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<'GREETD'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --asterisks --sessions /usr/local/share/wayland-sessions:/usr/share/wayland-sessions"
user = "greeter"
GREETD

# --- user config (idempotent) ---
QS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/apollo"
mkdir -p "$QS_DIR"
if [[ ! -f "$QS_DIR/shell.qml" ]]; then
  # migrate from old universe config if present
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

cat <<'DONE'

============================================================
Apollo install finished.

Installed / configured:
  - Apollo DE: KWin + Breeze + Quickshell (no plasmashell)
  - NVIDIA proprietary driver + modeset=1 (Wayland)
  - greetd + tuigreet (NOT SDDM)
  - NetworkManager + BlueZ

Next:
  1) reboot
  2) at tuigreet, pick session: "Apollo"
  3) edit shell:  ~/.config/quickshell/apollo/shell.qml
  4) edit kwin:   ~/.config/kwinrc

NVIDIA note:
  - Closed driver package is `nvidia`. On some new GPUs switch to `nvidia-open`.

apollod:
  - Planned Go daemon for your unified settings center
    (Wi-Fi, Bluetooth, monitors, Quickshell look/feel, keybinds, exec).
  - Not installed yet; start-apollo.sh launches it when on PATH.
  - (old name was universed; both work until the rename lands)

Re-run safely: ./install.sh  (existing user configs are kept)
============================================================
DONE

#!/usr/bin/env bash
# Apollo / Universe KWin + Quickshell — fresh Arch TTY installer
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
  # compositor + decorations (not plasmashell)
  kwin
  breeze
  kglobalaccel
  kglobalacceld
  kscreenlocker
  # portals / auth
  xdg-desktop-portal
  xdg-desktop-portal-kde
  polkit-kde-agent
  # Qt / Wayland
  qt6-wayland
  qt6-declarative
  qt6-svg
  qt6-multimedia
  qt6-5compat
  # audio
  pipewire
  wireplumber
  # greeter (TTY UI; replaces SDDM)
  greetd
  greetd-tuigreet
  # NVIDIA proprietary stack + Wayland bits
  # Use nvidia-open instead of nvidia on very new GPUs if the closed driver fails.
  nvidia
  nvidia-utils
  egl-wayland
  libglvnd
  # utilities
  wl-clipboard
  libnotify
  networkmanager
  bluez
  bluez-utils
  # AUR / build
  base-devel
  git
)

info "installing official packages..."
sudo pacman -Syu --needed --noconfirm "${PACMAN_PKGS[@]}"

# Prefer greetd over SDDM if SDDM was pulled in somehow
if systemctl list-unit-files sddm.service >/dev/null 2>&1; then
  sudo systemctl disable sddm.service 2>/dev/null || true
  info "disabled sddm.service (using greetd + tuigreet instead)"
fi

# --- NVIDIA modesetting (needed for Wayland compositors) ---
info "configuring NVIDIA DRM modeset..."
sudo tee /etc/modprobe.d/nvidia.conf >/dev/null <<'NVIDIA'
# Required for Wayland (KWin) with the proprietary driver
options nvidia_drm modeset=1
options nvidia_drm fbdev=1
NVIDIA

# Ensure early load via mkinitcpio when using the stock linux kernel
if [[ -f /etc/mkinitcpio.conf ]]; then
  if ! grep -qE '(^| )nvidia( |$)' /etc/mkinitcpio.conf; then
    # Append NVIDIA modules if MODULES=() is empty-ish; safest: ensure line contains them
    if grep -q '^MODULES=' /etc/mkinitcpio.conf; then
      sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
      # Clean double spaces / empty leading
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

# --- install session files ---
SHARE_DIR=/usr/local/share/universe-kwin
BIN_WRAPPER=/usr/local/bin/universe-kwin-session
DESKTOP_DST=/usr/local/share/wayland-sessions/universe-kwin.desktop

info "installing session scripts to $SHARE_DIR ..."
sudo mkdir -p "$SHARE_DIR/scripts" /usr/local/share/wayland-sessions /usr/local/bin
sudo install -m 0755 "$ROOT/scripts/start-universe.sh" "$SHARE_DIR/scripts/start-universe.sh"
sudo tee "$BIN_WRAPPER" >/dev/null <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
export UNIVERSE_KWIN_ROOT=/usr/local/share/universe-kwin
exec bash "$UNIVERSE_KWIN_ROOT/scripts/start-universe.sh"
WRAP
sudo chmod 0755 "$BIN_WRAPPER"
sudo install -m 0644 "$ROOT/session/universe-kwin.desktop" "$DESKTOP_DST"

# --- greetd + tuigreet ---
info "configuring greetd + tuigreet..."
sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<'GREETD'
[terminal]
vt = 1

[default_session]
# TUI greeter; sessions come from wayland-sessions .desktop files
command = "tuigreet --time --remember --asterisks --sessions /usr/local/share/wayland-sessions:/usr/share/wayland-sessions"
user = "greeter"
GREETD

# --- user config (idempotent) ---
QS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/universe"
mkdir -p "$QS_DIR"
if [[ ! -f "$QS_DIR/shell.qml" ]]; then
  install -m 0644 "$ROOT/config/quickshell/shell.qml" "$QS_DIR/shell.qml"
  info "wrote $QS_DIR/shell.qml"
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
Apollo / Universe KWin install finished.

Installed / configured:
  - KWin + Breeze + Quickshell (no plasmashell)
  - NVIDIA proprietary driver + modeset=1 (Wayland)
  - greetd + tuigreet (NOT SDDM)
  - NetworkManager + BlueZ

Next:
  1) reboot
  2) at tuigreet, pick session: "Universe (KWin + Quickshell)"
  3) edit shell:  ~/.config/quickshell/universe/shell.qml
  4) edit kwin:   ~/.config/kwinrc

NVIDIA note:
  - Closed driver package is `nvidia`. On some new GPUs switch to `nvidia-open`.
  - After kernel updates, keep headers/driver in sync.

universed:
  - That name is the planned Go daemon for your unified settings center
    (Wi-Fi, Bluetooth, monitors, Quickshell look/feel, keybinds, exec).
  - Not installed yet; start-universe.sh will launch it when it is on PATH.

Re-run safely: ./install.sh  (existing user configs are kept)
============================================================
DONE

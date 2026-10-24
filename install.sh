#!/usr/bin/env bash
# Universe KWin + Quickshell — fresh Arch TTY installer
# Usage (as your normal user, with sudo):
#   git clone <this-repo> ~/universe-kwin && cd ~/universe-kwin && ./install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="[universe-kwin]"

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
  # compositor + decorations stack (pulls KDE frameworks; not plasmashell)
  kwin
  breeze
  kglobalaccel
  kglobalacceld
  kscreenlocker
  # portals / auth
  xdg-desktop-portal
  xdg-desktop-portal-kde
  polkit-kde-agent
  # Qt / Wayland bits Quickshell & KWin expect
  qt6-wayland
  qt6-declarative
  qt6-svg
  qt6-multimedia
  qt6-5compat
  # audio session
  pipewire
  wireplumber
  # display manager + utilities
  sddm
  wl-clipboard
  libnotify
  # networking defaults for a usable first boot (settings center later)
  networkmanager
  bluez
  bluez-utils
  # build helpers for yay / AUR
  base-devel
  git
)

info "installing official packages..."
sudo pacman -Syu --needed --noconfirm "${PACMAN_PKGS[@]}"

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
sudo install -m 0755 "$ROOT/scripts/universe-kwin-session" "$BIN_WRAPPER"
sudo install -m 0644 "$ROOT/session/universe-kwin.desktop" "$DESKTOP_DST"

# Point wrapper at installed share dir
sudo tee "$BIN_WRAPPER" >/dev/null <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
export UNIVERSE_KWIN_ROOT=/usr/local/share/universe-kwin
exec bash "$UNIVERSE_KWIN_ROOT/scripts/start-universe.sh"
WRAP
sudo chmod 0755 "$BIN_WRAPPER"

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
info "enabling NetworkManager, bluetooth, SDDM..."
sudo systemctl enable NetworkManager.service || warn "could not enable NetworkManager"
sudo systemctl enable bluetooth.service || warn "could not enable bluetooth"
sudo systemctl enable sddm.service

# Prefer Universe session as SDDM default when unset
SDDM_CONF_DIR=/etc/sddm.conf.d
sudo mkdir -p "$SDDM_CONF_DIR"
if [[ ! -f "$SDDM_CONF_DIR/10-universe-kwin.conf" ]]; then
  sudo tee "$SDDM_CONF_DIR/10-universe-kwin.conf" >/dev/null <<'SDDM'
[Autologin]
# Session=universe-kwin.desktop
# User=youruser

[General]
# SDDM lists wayland-sessions; pick "Universe (KWin + Quickshell)" at login
SDDM
  info "wrote $SDDM_CONF_DIR/10-universe-kwin.conf"
fi

cat <<'DONE'

============================================================
Universe KWin install finished.

Next:
  1) reboot  (or: sudo systemctl start sddm)
  2) at SDDM, choose session: "Universe (KWin + Quickshell)"
  3) edit shell:  ~/.config/quickshell/universe/shell.qml
  4) edit kwin:   ~/.config/kwinrc

Notes:
  - plasmashell is NOT installed/started on purpose
  - tiling: install a KWin Script later (e.g. Krohnkite) after first graphical login
  - universed (Go settings daemon) is optional; start-universe.sh will launch it if on PATH

Re-run safely: ./install.sh  (configs you already edited are kept)
============================================================
DONE

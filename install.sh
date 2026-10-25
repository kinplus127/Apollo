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

# One sudo password for the whole install. The background refresh keeps the
# timestamp alive across long pacman/yay builds. sudo -n -v never prompts
# and stops if timestamp_timeout is 0.
start_sudo_keepalive() {
  while true; do
    sudo -n -v || exit 0
    sleep 50
    kill -0 "$$" 2>/dev/null || exit 0
  done
}

cleanup_sudo_keepalive() {
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi
}

apply_root_setup() {
  local fish_bin="$1"
  info "applying root setup once (login shell, session files, greetd, services)..."
  sudo bash -s -- "$INSTALL_USER" "$ROOT" "$fish_bin" <<'EOS'
set -euo pipefail
user="$1"
root="$2"
fish_bin="$3"
log() { printf '[apollo] %s\n' "$*"; }

if [[ -n "$fish_bin" && -x "$fish_bin" ]]; then
  if ! grep -qxF "$fish_bin" /etc/shells 2>/dev/null; then
    log "adding $fish_bin to /etc/shells"
    printf '%s\n' "$fish_bin" >>/etc/shells
  fi
  current="$(getent passwd "$user" | cut -d: -f7 || true)"
  if [[ "$current" != "$fish_bin" ]]; then
    log "setting login shell for $user → $fish_bin"
    chsh -s "$fish_bin" "$user"
  else
    log "login shell already fish for $user"
  fi
fi

if [[ ! -x /usr/bin/tuigreet ]]; then
  echo "[apollo] error: /usr/bin/tuigreet is missing (package greetd-tuigreet)." >&2
  exit 1
fi
if [[ ! -f "$root/config/greetd/config.toml" ]]; then
  echo "[apollo] error: this checkout has no config/greetd/config.toml." >&2
  exit 1
fi
if grep -q '^\[initial_session\]' "$root/config/greetd/config.toml"; then
  echo "[apollo] error: config/greetd/config.toml must not contain [initial_session] (autologin)." >&2
  exit 1
fi
if systemctl list-unit-files --no-legend 'sddm.service' 2>/dev/null | grep -q .; then
  systemctl disable sddm.service >/dev/null 2>&1 || true
  log "disabled sddm.service"
fi

share=/usr/local/share/apollo
log "installing session scripts to $share"
mkdir -p "$share/scripts" "$share/pam" /usr/local/share/wayland-sessions /usr/local/bin \
  /usr/local/share/applications /etc/greetd /etc/pacman.d/hooks
install -m 0755 "$root/scripts/start-apollo.sh" "$share/scripts/start-apollo.sh"
install -m 0755 "$root/scripts/apollo-session" /usr/local/bin/apollo-session
install -m 0755 "$root/scripts/apollo-lock.sh" "$share/scripts/apollo-lock.sh"
install -m 0755 "$root/scripts/apollo-logout.sh" "$share/scripts/apollo-logout.sh"
rm -f /usr/local/bin/apollo-theme-nt "$share/scripts/apollo-theme-nt.sh"
install -m 0755 "$root/scripts/kscreenlocker-greet-wrapper.sh" "$share/scripts/kscreenlocker-greet-wrapper.sh"
install -m 0755 "$root/scripts/apollo-setup-lock.sh" "$share/scripts/apollo-setup-lock.sh"
install -m 0755 "$root/scripts/apollo-remove-lock-wrap.sh" "$share/scripts/apollo-remove-lock-wrap.sh"
install -m 0644 "$root/config/pam/kde" "$share/pam/kde"
rm -rf "$share/lockscreen"
mkdir -p "$share/lockscreen/contents/lockscreen"
install -m 0644 "$root/config/lockscreen/metadata.json" "$share/lockscreen/metadata.json"
install -m 0644 "$root/config/lockscreen/contents/lockscreen/LockScreen.qml" \
  "$share/lockscreen/contents/lockscreen/LockScreen.qml"
install -m 0644 "$root/config/pacman/hooks/apollo-kscreenlocker-greet.hook" \
  /etc/pacman.d/hooks/apollo-kscreenlocker-greet.hook
install -m 0644 "$root/config/pacman/hooks/apollo-kscreenlocker-greet-remove.hook" \
  /etc/pacman.d/hooks/apollo-kscreenlocker-greet-remove.hook
install -m 0644 "$root/session/apollo.desktop" /usr/local/share/wayland-sessions/apollo.desktop
install -m 0644 "$root/session/apollo-lock.desktop" /usr/local/share/applications/apollo-lock.desktop
install -m 0644 "$root/session/apollo-logout.desktop" /usr/local/share/applications/apollo-logout.desktop
install -m 0644 "$root/session/apollo-screenshot-region.desktop" /usr/local/share/applications/apollo-screenshot-region.desktop
install -m 0644 "$root/session/apollo-screenshot-full.desktop" /usr/local/share/applications/apollo-screenshot-full.desktop
# kscreenlocker is already installed. Install the locker PAM stack, the
# Apollo lock screen, and the greeter wrapper.
"$share/scripts/apollo-setup-lock.sh"
rm -f /usr/local/bin/universe-kwin-session \
  /usr/local/share/wayland-sessions/universe-kwin.desktop
rm -rf /usr/local/share/universe-kwin

install -m 0644 "$root/config/greetd/config.toml" /etc/greetd/config.toml
if ! getent passwd greeter >/dev/null; then
  log "creating system user greeter"
  useradd --system --user-group --home-dir /var/lib/greeter --create-home --shell /usr/bin/nologin greeter
fi
install -d -m 0755 /var/cache/tuigreet
chown greeter:greeter /var/cache/tuigreet
log "greetd asks for a password via tuigreet; autologin is not configured"

log "enabling NetworkManager, bluetooth, greetd..."
systemctl enable NetworkManager.service || log "warning: could not enable NetworkManager"
systemctl enable bluetooth.service || log "warning: could not enable bluetooth"
systemctl enable greetd.service
EOS
}

# fish started from the session does not always inherit these directories.
install_fish_path() {
  local dest="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d"
  mkdir -p "$dest"
  install -m 0644 "$ROOT/config/fish/conf.d/apollo.fish" "$dest/apollo.fish"
  info "wrote $dest/apollo.fish (PATH includes /usr/local/bin and ~/.local/bin)"
}

# Session files are root-owned. Abort when the greeter config or entrypoint
# did not land, and when an old NT theme command is still installed.
require_session_install() {
  local bin="/usr/local/bin/apollo-session"
  local greetd_cfg="/etc/greetd/config.toml"

  [[ -x "$bin" ]] || die "missing $bin. Root setup did not finish. Re-run ./install.sh from this checkout."
  [[ -f "$greetd_cfg" ]] || die "missing $greetd_cfg. Root setup did not finish. Re-run ./install.sh from this checkout."
  if grep -q '^\[initial_session\]' "$greetd_cfg"; then
    die "$greetd_cfg still has [initial_session] (autologin). Re-run ./install.sh from this checkout."
  fi
  if ! grep -q 'tuigreet' "$greetd_cfg" || ! grep -q '/usr/local/bin/apollo-session' "$greetd_cfg"; then
    die "$greetd_cfg does not start tuigreet into Apollo. Re-run ./install.sh from this checkout."
  fi
  if [[ -e /usr/local/bin/apollo-theme-nt || -e /usr/local/share/apollo/scripts/apollo-theme-nt.sh ]]; then
    die "NT theme command is still installed. Re-run ./install.sh from this checkout."
  fi
  info "apollo-session and greetd password login are installed"
}

if [[ ${EUID:-0} -eq 0 ]]; then
  die "run as a normal user (script will call sudo). do not run as root."
fi

need_cmd sudo
need_cmd pacman
need_cmd install

if [[ ! -f /etc/arch-release ]]; then
  die "this installer targets Arch Linux (/etc/arch-release not found)"
fi

# Ask once. pacman, yay, greetd, and /usr/local reuse this timestamp.
info "enter your sudo password once; later privileged steps reuse it"
sudo -v
SUDO_KEEPALIVE_PID=""
trap cleanup_sudo_keepalive EXIT
start_sudo_keepalive >/dev/null 2>&1 &
SUDO_KEEPALIVE_PID=$!

INSTALL_USER="${SUDO_USER:-$USER}"
if [[ "$INSTALL_USER" == root ]] || [[ -z "$INSTALL_USER" ]]; then
  INSTALL_USER="$(id -un)"
fi

# --- packages ---
PACMAN_PKGS=(
  kwin
  breeze
  breeze-icons
  # Qt platform theme: Breeze colours, icons, and fonts from kdeglobals.
  # This does not install plasmashell.
  plasma-integration
  dbus
  # Present for KWin and the screen locker. Apollo does not register
  # shortcuts and does not start kglobalacceld.
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
  # Pulse socket for pavucontrol-qt. Provides pulse-native-provider.
  # Do not install pulseaudio.
  pipewire-pulse
  # Password greeter. config/greetd/config.toml has no autologin block.
  greetd
  greetd-tuigreet
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
  cliphist
  wl-clip-persist
  spectacle
  # Qt file manager. The desktop module is OnlyShowIn=LXQt and does not
  # start in an Apollo session.
  pcmanfm-qt
  # Qt PulseAudio mixer (pavucontrol-qt). No shell button yet.
  pavucontrol-qt
  libnotify
  networkmanager
  bluez
  bluez-utils
  # Sucheng (Quick3, zh_HK) comes from fcitx5-table-extra; Mozc is romaji.
  fcitx5
  fcitx5-qt
  fcitx5-gtk
  fcitx5-configtool
  fcitx5-chinese-addons
  fcitx5-table-extra
  fcitx5-mozc
  base-devel
  git
  fontconfig
  ttf-nerd-fonts-symbols
  ttf-nerd-fonts-symbols-mono
  gsettings-desktop-schemas
)

# NVIDIA modeset: shipped by Arch nvidia-utils (no extra modprobe/mkinitcpio here).

# awww replaced swww. pacman -Si does not need root. Do not ask the root
# shell to write a user-owned temp file: a private /tmp rejects that, and
# the whole install then stops before the session files are copied.
info "installing official packages..."
AWWW_FROM_OFFICIAL=0
if pacman -Si awww >/dev/null 2>&1; then
  PACMAN_PKGS+=(awww)
  AWWW_FROM_OFFICIAL=1
  info "awww is in the official repositories; including it in this pacman transaction"
else
  info "awww is not in the official repositories; will use AUR awww-git"
fi
sudo pacman -Syu --needed --noconfirm "${PACMAN_PKGS[@]}"

# --- fish, session files, greetd, services: one root shell ---
FISH_BIN="$(command -v fish || true)"
if [[ -z "$FISH_BIN" ]]; then
  warn "fish binary not found after install"
fi
root_status=0
apply_root_setup "$FISH_BIN" || root_status=$?
install_fish_path
if [[ "$root_status" -ne 0 ]]; then
  die "root setup failed (exit ${root_status}). /usr/local session files may be incomplete. Re-run ./install.sh from this checkout."
fi
require_session_install

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

# Refresh the timestamp before builds. No prompt while the keepalive holds.
sudo -v

install_yay

AUR_PKGS=(quickshell brave-origin-bin ttf-apple-emoji)
if [[ "$AWWW_FROM_OFFICIAL" -ne 1 ]]; then
  info "awww is not in the official repositories; installing awww-git from AUR"
  AUR_PKGS+=(awww-git)
fi
info "installing AUR packages: ${AUR_PKGS[*]}"
yay -S --needed --noconfirm "${AUR_PKGS[@]}"

# --- fonts ---
# IBM Plex release zips mix in woff/woff2, so copy desktop OTF only
# (fonts/complete/otf, hinted when CJK splits hinted/unhinted).
# Noroshi has no release assets; use hinted TTF (upstream prefers TTF over OTF).

has_font_file() {
  local dir="$1" ext="$2" found
  found="$(find "$dir" -type f -name "*.${ext}" -print -quit 2>/dev/null || true)"
  [[ -n "$found" ]]
}

copy_desktop_fonts() {
  local src="$1" dest="$2" ext="$3"
  local f count=0
  mkdir -p "$dest"
  while IFS= read -r -d '' f; do
    install -m 0644 "$f" "$dest/$(basename "$f")"
    count=$((count + 1))
  done < <(find "$src" -maxdepth 1 -type f -iname "*.${ext}" -print0)
  [[ "$count" -gt 0 ]] || die "no ${ext} files in $src"
  info "copied ${count} ${ext} → $dest"
}

reject_web_fonts() {
  local dir="$1" found
  found="$(find "$dir" -type f \( -iname '*.woff' -o -iname '*.woff2' -o -iname '*.eot' \) -print -quit 2>/dev/null || true)"
  [[ -z "$found" ]] || die "refusing web font in $dir ($found)"
}

install_ibm_plex() {
  (
    local tmp dest stamp rev dir pkg
    local -a plex_font_dirs
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT
    dest="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/ibm-plex"
    rev="$(GIT_TERMINAL_PROMPT=0 git ls-remote https://github.com/IBM/plex.git HEAD | awk 'NR==1 { print $1 }')"
    [[ -n "$rev" ]] || die "could not resolve IBM Plex HEAD"
    stamp="$dest/.apollo-source"
    if [[ -f "$stamp" && "$(<"$stamp")" == "$rev" ]] && has_font_file "$dest" otf; then
      info "IBM Plex desktop fonts already present ($rev)"
      exit 0
    fi
    info "installing IBM Plex desktop OTF from GitHub..."
    plex_font_dirs=(
      packages/plex-sans/fonts/complete/otf
      packages/plex-serif/fonts/complete/otf
      packages/plex-mono/fonts/complete/otf
      packages/plex-sans-condensed/fonts/complete/otf
      packages/plex-sans-jp/fonts/complete/otf/hinted
      packages/plex-sans-kr/fonts/complete/otf
      packages/plex-sans-sc/fonts/complete/otf/hinted
      packages/plex-sans-tc/fonts/complete/otf/hinted
      packages/plex-sans-arabic/fonts/complete/otf
      packages/plex-sans-hebrew/fonts/complete/otf
      packages/plex-sans-devanagari/fonts/complete/otf
      packages/plex-sans-thai/fonts/complete/otf
      packages/plex-sans-thai-looped/fonts/complete/otf
      packages/plex-math/fonts/complete/otf
    )
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 --filter=blob:none --sparse \
      https://github.com/IBM/plex.git "$tmp/plex"
    git -C "$tmp/plex" sparse-checkout set --cone "${plex_font_dirs[@]}"
    rm -rf "$dest"
    mkdir -p "$dest"
    for dir in "${plex_font_dirs[@]}"; do
      pkg="${dir#packages/}"
      pkg="${pkg%%/*}"
      copy_desktop_fonts "$tmp/plex/$dir" "$dest/$pkg" otf
    done
    reject_web_fonts "$dest"
    printf '%s\n' "$rev" >"$stamp"
    info "IBM Plex installed → $dest ($rev)"
  )
}

install_noroshi() {
  (
    local tmp dest stamp tag
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT
    dest="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/noroshi"
    tag="$(
      GIT_TERMINAL_PROMPT=0 git ls-remote --tags --refs https://github.com/Honoka55/noroshi.git \
        | awk -F/ '{ print $NF }' \
        | grep -E '^v[0-9]+\.[0-9]+' \
        | sort -V \
        | tail -n 1 \
        || true
    )"
    [[ -n "$tag" ]] || die "could not resolve Noroshi release tag"
    stamp="$dest/.apollo-source"
    if [[ -f "$stamp" && "$(<"$stamp")" == "$tag" ]] && has_font_file "$dest" ttf; then
      info "Noroshi Code already present ($tag)"
      exit 0
    fi
    info "installing Noroshi Code hinted TTF from GitHub ($tag)..."
    GIT_TERMINAL_PROMPT=0 git -c advice.detachedHead=false clone --depth 1 --filter=blob:none --sparse --branch "$tag" \
      https://github.com/Honoka55/noroshi.git "$tmp/noroshi"
    git -C "$tmp/noroshi" sparse-checkout set --cone fonts/NoroshiCode/ttf/hinted
    rm -rf "$dest"
    mkdir -p "$dest"
    copy_desktop_fonts "$tmp/noroshi/fonts/NoroshiCode/ttf/hinted" "$dest" ttf
    reject_web_fonts "$dest"
    printf '%s\n' "$tag" >"$stamp"
    info "Noroshi Code installed → $dest ($tag)"
  )
}

set_ini_key() {
  local file="$1" section="$2" key="$3" value="$4"
  mkdir -p "$(dirname "$file")"
  if [[ ! -f "$file" ]]; then
    printf '[%s]\n%s=%s\n' "$section" "$key" "$value" >"$file"
    return 0
  fi
  if grep -q "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    return 0
  fi
  if grep -q "^\\[${section}\\]" "$file"; then
    sed -i "/^\\[${section}\\]/a ${key}=${value}" "$file"
  else
    printf '\n[%s]\n%s=%s\n' "$section" "$key" "$value" >>"$file"
  fi
}

set_kitty_key() {
  local file="$1" key="$2" value="$3"
  if grep -qE "^[[:space:]]*${key}([[:space:]]|$)" "$file"; then
    sed -i -E "s|^[[:space:]]*${key}[[:space:]].*|${key} ${value}|" "$file"
  else
    printf '%s %s\n' "$key" "$value" >>"$file"
  fi
}

apply_font_configs() {
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
  local fc_dst="$cfg/fontconfig/conf.d/60-apollo-fonts.conf"
  local gtk_src gtk_dst kde_dst kitty_dst

  mkdir -p "$(dirname "$fc_dst")"
  install -m 0644 "$ROOT/config/fontconfig/conf.d/60-apollo-fonts.conf" "$fc_dst"
  info "wrote $fc_dst"

  for gtk_src in gtk-3.0 gtk-4.0; do
    gtk_dst="$cfg/$gtk_src/settings.ini"
    mkdir -p "$(dirname "$gtk_dst")"
    if [[ ! -f "$gtk_dst" ]]; then
      install -m 0644 "$ROOT/config/$gtk_src/settings.ini" "$gtk_dst"
      info "wrote $gtk_dst"
    else
      set_ini_key "$gtk_dst" Settings gtk-font-name "IBM Plex Sans 11"
      info "updated gtk-font-name in $gtk_dst"
    fi
  done

  kde_dst="$cfg/kdeglobals"
  if [[ ! -f "$kde_dst" ]]; then
    install -m 0644 "$ROOT/config/kdeglobals" "$kde_dst"
    info "wrote $kde_dst"
  else
    set_ini_key "$kde_dst" General font "IBM Plex Sans,11,-1,5,50,0,0,0,0,0"
    set_ini_key "$kde_dst" General fixed "Noroshi Code,11,-1,5,50,0,0,0,0,0"
    set_ini_key "$kde_dst" General menuFont "IBM Plex Sans,11,-1,5,50,0,0,0,0,0"
    set_ini_key "$kde_dst" General smallestReadableFont "IBM Plex Sans,8,-1,5,50,0,0,0,0,0"
    set_ini_key "$kde_dst" General toolBarFont "IBM Plex Sans,11,-1,5,50,0,0,0,0,0"
    info "updated font keys in $kde_dst"
  fi

  kitty_dst="$cfg/kitty/kitty.conf"
  mkdir -p "$(dirname "$kitty_dst")"
  if [[ ! -f "$kitty_dst" ]]; then
    install -m 0644 "$ROOT/config/kitty/kitty.conf" "$kitty_dst"
    info "wrote $kitty_dst"
  else
    set_kitty_key "$kitty_dst" font_family "Noroshi Code"
    set_kitty_key "$kitty_dst" bold_font auto
    set_kitty_key "$kitty_dst" italic_font auto
    set_kitty_key "$kitty_dst" bold_italic_font auto
    info "updated font_family in $kitty_dst"
  fi
}

apply_gsettings_fonts() {
  local failed=0
  local -a runner=()
  if ! command -v gsettings >/dev/null 2>&1; then
    warn "gsettings not found; skipped GSettings font keys"
    return 0
  fi
  if ! gsettings list-schemas 2>/dev/null | grep -qx 'org.gnome.desktop.interface'; then
    warn "org.gnome.desktop.interface schema missing; skipped GSettings font keys"
    return 0
  fi
  if command -v dbus-run-session >/dev/null 2>&1; then
    runner=(dbus-run-session --)
  fi
  "${runner[@]}" gsettings set org.gnome.desktop.interface font-name 'IBM Plex Sans 11' || failed=1
  "${runner[@]}" gsettings set org.gnome.desktop.interface document-font-name 'IBM Plex Sans 11' || failed=1
  "${runner[@]}" gsettings set org.gnome.desktop.interface monospace-font-name 'Noroshi Code 11' || failed=1
  if [[ "$failed" -ne 0 ]]; then
    warn "one or more GSettings font keys were not applied"
  else
    info "set GSettings interface fonts (IBM Plex Sans 11, Noroshi Code 11)"
  fi
}

install_ibm_plex
install_noroshi

if command -v fc-cache >/dev/null 2>&1; then
  info "refreshing font cache..."
  fc-cache -f
else
  warn "fc-cache not found; font cache not refreshed"
fi

apply_font_configs
apply_gsettings_fonts

# Session binaries and greetd were installed in apply_root_setup.
# These desktop files are for the user session and stay unprivileged.
USER_APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$USER_APP_DIR"
install -m 0644 "$ROOT/session/apollo-lock.desktop" "$USER_APP_DIR/apollo-lock.desktop"
install -m 0644 "$ROOT/session/apollo-logout.desktop" "$USER_APP_DIR/apollo-logout.desktop"
install -m 0644 "$ROOT/session/apollo-screenshot-region.desktop" "$USER_APP_DIR/apollo-screenshot-region.desktop"
install -m 0644 "$ROOT/session/apollo-screenshot-full.desktop" "$USER_APP_DIR/apollo-screenshot-full.desktop"

# --- LazyVim (Neovim distro) ---
NVIM_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
if [[ ! -e "$NVIM_CFG" ]]; then
  info "installing LazyVim starter → $NVIM_CFG"
  git clone --depth=1 https://github.com/LazyVim/starter "$NVIM_CFG"
  rm -rf "$NVIM_CFG/.git"
else
  info "keep existing $NVIM_CFG (not overwriting LazyVim/neovim config)"
fi


# Shortcuts are intentionally disabled. This writes the disabled stub when
# ~/.config/kglobalshortcutsrc is missing, and only clears Meta/Super on the
# Apollo actions a previous install already wrote. It does not add bindings.
# Re-enable: config/kglobalshortcutsrc.snippet.
set_section_key() {
  local file="$1" section="$2" key="$3" value="$4" tmp
  mkdir -p "$(dirname "$file")"
  [[ -f "$file" ]] || : >"$file"
  tmp="$(mktemp "$(dirname "$file")/.apollo-ini.XXXXXX")"
  awk -v section="$section" -v key="$key" -v value="$value" '
    BEGIN { header = "[" section "]" }
    $0 == header { insec = 1; found_sec = 1; print; next }
    /^\[/ {
      if (insec && !found_key) { print key "=" value; found_key = 1 }
      insec = 0
    }
    insec && index($0, key "=") == 1 { print key "=" value; found_key = 1; next }
    { print }
    END {
      if (!found_sec) {
        print ""
        print header
        print key "=" value
      } else if (insec && !found_key) {
        print key "=" value
      }
    }
  ' "$file" >"$tmp"
  chmod 0644 "$tmp"
  mv -f "$tmp" "$file"
}

unbind_service_launch() {
  local file="$1" section="$2" block
  block="$(sed -n "/^\\[services\\]\\[${section}\\]/,/^\\[/p" "$file" || true)"
  [[ -n "$block" ]] || return 0
  if ! printf '%s\n' "$block" | grep -q '^_launch=.*\(Meta\|Super\)'; then
    return 0
  fi
  sed -i "/^\\[services\\]\\[${section}\\]/,/^\\[/s/^_launch=[^,]*,[^,]*,/_launch=none,none,/" "$file"
  info "unbound ${section} in $file"
}

apply_disabled_shortcuts() {
  local dest="${XDG_CONFIG_HOME:-$HOME/.config}/kglobalshortcutsrc"
  local snip="$ROOT/config/kglobalshortcutsrc.snippet"
  local accel="${XDG_DATA_HOME:-$HOME/.local/share}/kglobalaccel/kitty.desktop"
  local section
  [[ -f "$snip" ]] || die "missing $snip"
  mkdir -p "$(dirname "$dest")"
  if [[ ! -f "$dest" ]]; then
    install -m 0644 "$snip" "$dest"
    info "wrote $dest (shortcuts disabled; no Meta/Super bindings)"
  else
    if grep -q '^Window Close=.*\(Meta\|Super\)+Q' "$dest"; then
      sed -i 's/^Window Close=.*/Window Close=Alt+F4,Alt+F4,Close Window/' "$dest"
      info "removed Meta/Super+Q from Window Close in $dest"
    fi
    if grep -q '^Edit Tiles=.*\(Meta\|Super\)' "$dest"; then
      sed -i 's/^Edit Tiles=.*/Edit Tiles=none,none,Toggle Tiling/' "$dest"
      info "unbound Edit Tiles in $dest"
    fi
    for section in kitty.desktop apollo-lock.desktop apollo-logout.desktop \
      apollo-screenshot-region.desktop apollo-screenshot-full.desktop; do
      unbind_service_launch "$dest" "$section"
    done
    info "left other shortcuts in $dest unchanged"
  fi
  if [[ -f "$accel" && -f "$ROOT/session/kitty.desktop" ]] && cmp -s "$accel" "$ROOT/session/kitty.desktop"; then
    rm -f "$accel"
    info "removed shortcut fallback $accel"
  fi
}

# Drop NT Legacy / Aurorae assets and point decoration, colours, and icons
# back at stock Breeze when a previous install selected that theme.
remove_nt_legacy() {
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
  local data="${XDG_DATA_HOME:-$HOME/.local/share}"
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}"
  local kwinrc="$cfg/kwinrc"
  local kdeglobals="$cfg/kdeglobals"
  local pcmanfm="$cfg/pcmanfm-qt/default/settings.conf"
  local tmp

  rm -f "${HOME}/.local/bin/apollo-theme-nt"
  rm -rf \
    "$data/aurorae/themes/NTLegacyWin98" \
    "$data/aurorae/themes/NTLegacyWin98Nacht" \
    "$data/icons/NTLegacyIcons" \
    "$data/icons/NTLegacyIconsNacht" \
    "$data/apollo/nt-legacy"
  rm -f \
    "$data/color-schemes/NTLegacyWin98.colors" \
    "$data/color-schemes/NTLegacyWin98Nacht.colors" \
    "$cache/apollo/windows-style.ok"

  if [[ -f "$kwinrc" ]] && grep -Eq 'aurorae|NTLegacy|__aurorae__' "$kwinrc"; then
    set_section_key "$kwinrc" org.kde.kdecoration2 library "org.kde.breeze"
    set_section_key "$kwinrc" org.kde.kdecoration2 theme "Breeze"
    info "reset window decoration in $kwinrc to Breeze"
  fi

  if [[ -f "$kdeglobals" ]] && grep -q 'NTLegacy' "$kdeglobals"; then
    tmp="$(mktemp "$(dirname "$kdeglobals")/.apollo-breeze.XXXXXX")"
    awk '
      /^\[/ { drop = ($0 ~ /^\[Colors:/ || $0 ~ /^\[ColorEffects:/) }
      !drop { print }
    ' "$kdeglobals" >"$tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "$kdeglobals"
    sed -i \
      -e '/^ColorSchemeHash=/d' \
      -e '/^contrast=/d' \
      -e '/^frameContrast=/d' \
      -e '/^activeBackground=/d' \
      -e '/^activeForeground=/d' \
      -e '/^inactiveBackground=/d' \
      -e '/^inactiveForeground=/d' \
      -e '/^activeBlend=/d' \
      -e '/^inactiveBlend=/d' \
      "$kdeglobals"
    set_section_key "$kdeglobals" General ColorScheme "Breeze"
    set_section_key "$kdeglobals" UiSettings ColorScheme "Breeze"
    set_section_key "$kdeglobals" Icons Theme "breeze"
    set_section_key "$kdeglobals" KDE widgetStyle "breeze"
    info "reset colours, icons, and widget style in $kdeglobals to Breeze"
  fi

  if [[ -f "$pcmanfm" ]] && grep -q 'NTLegacy' "$pcmanfm"; then
    set_section_key "$pcmanfm" System IconThemeName "breeze"
    set_section_key "$pcmanfm" System FallbackIconThemeName "breeze"
    info "reset PCManFM-Qt icons in $pcmanfm to breeze"
  fi
}

apply_disabled_shortcuts

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

FCITX_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fcitx5"
if [[ ! -e "$FCITX_DIR/profile" ]]; then
  mkdir -p "$FCITX_DIR"
  install -m 0644 "$ROOT/config/fcitx5/profile" "$FCITX_DIR/profile"
  info "wrote $FCITX_DIR/profile (Sucheng Quick3 + Mozc)"
else
  info "keep existing $FCITX_DIR/profile"
fi

KWINRC="${XDG_CONFIG_HOME:-$HOME/.config}/kwinrc"
mkdir -p "$(dirname "$KWINRC")"
if [[ ! -f "$KWINRC" ]]; then
  install -m 0644 "$ROOT/config/kwin/kwinrc.snippet" "$KWINRC"
  info "wrote $KWINRC (Breeze decoration)"
else
  info "keep existing $KWINRC"
fi
remove_nt_legacy

cat <<DONE

============================================================
Apollo install finished.

Installed / configured:
  - Apollo DE: KWin + Quickshell, Breeze decoration and colours (no plasmashell)
  - pcmanfm-qt (file manager), pavucontrol-qt (volume mixer)
  - NVIDIA: nvidia-open + nvidia-utils + libva-nvidia-driver
  - greetd + tuigreet: password login as the user you type (no autologin)
  - fish as login shell for ${INSTALL_USER}
  - kitty, yazi, neovim + LazyVim starter
  - fonts: IBM Plex OTF, Noroshi Code, Apple Color Emoji, Symbols Nerd Font
  - awww wallpaper daemon (random image from ~/Pictures/wallpapers/)
  - fcitx5: Sucheng (Quick3) + Mozc romaji
  - global shortcuts: disabled (no Meta/Super bindings from Apollo)
  - lock: kscreenlocker with Apollo's lock screen and PAM service kde
    Run /usr/local/share/apollo/scripts/apollo-lock.sh (Super+L is unbound)
  - Spectacle, cliphist, and wl-clip-persist are installed; no shortcut keys
  - NetworkManager + BlueZ

Next:
  1) reboot → tuigreet asks for username and password, then starts Apollo
  2) wallpapers: ~/Pictures/wallpapers/ (awww picks one at login)
  3) edit shell:  ~/.config/quickshell/apollo/shell.qml
  4) edit kwin:   ~/.config/kwinrc
     Decoration and colours are stock Breeze.
     Volume: pavucontrol-qt   Files: pcmanfm-qt
  5) shortcuts stay off until re-enabled (see config/kglobalshortcutsrc.snippet)
  6) lock: /usr/local/share/apollo/scripts/apollo-lock.sh
     Type the account password and press Unlock or Enter.
     The session should unlock. fcitx5 still works in applications.
     If the screen stays locked: Ctrl+Alt+F3, log in, then
     loginctl unlock-session SESSION_ID
     (loginctl list-sessions prints SESSION_ID)

NVIDIA:
  - modeset comes from Arch's nvidia-utils; egl-wayland is a dep of nvidia-utils

apollod:
  - Planned Go daemon for your unified settings center
    (Wi-Fi, Bluetooth, monitors, Quickshell look/feel, keybinds, exec).
  - Not installed yet; start-apollo.sh launches it when on PATH.

Re-run safely: ./install.sh  (existing user configs are kept; greetd config is rewritten)
============================================================
DONE

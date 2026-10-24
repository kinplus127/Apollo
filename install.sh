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
  breeze-icons
  # Aurorae draws NT Legacy title bars. kwin already depends on it; listed
  # so the decoration engine is not only a transitive dependency.
  aurorae
  # Qt platform theme: colours, icons, and widgetStyle from kdeglobals.
  # This does not install plasmashell.
  plasma-integration
  dbus
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
  cliphist
  wl-clip-persist
  spectacle
  # Qt file manager. Dolphin's capacity bar ignores the Windows widget
  # style; PCManFM-Qt follows it. The desktop module is OnlyShowIn=LXQt
  # and does not start in an Apollo session.
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

# --- wallpaper backend (awww; replaces swww — do not install swww) ---
if pacman -Si awww >/dev/null 2>&1; then
  info "installing awww from official repositories..."
  sudo pacman -S --needed --noconfirm awww
else
  info "awww not in the official repositories; installing awww-git from AUR..."
  yay -S --needed --noconfirm awww-git
fi

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

info "installing fontconfig, Nerd Font symbols, and gsettings schemas..."
sudo pacman -S --needed --noconfirm \
  fontconfig \
  ttf-nerd-fonts-symbols \
  ttf-nerd-fonts-symbols-mono \
  gsettings-desktop-schemas

info "installing ttf-apple-emoji from AUR..."
yay -S --needed --noconfirm ttf-apple-emoji

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

# --- install session files (Apollo brand) ---
SHARE_DIR=/usr/local/share/apollo
BIN_WRAPPER=/usr/local/bin/apollo-session
DESKTOP_DST=/usr/local/share/wayland-sessions/apollo.desktop

info "installing session scripts to $SHARE_DIR ..."
sudo mkdir -p "$SHARE_DIR/scripts" /usr/local/share/wayland-sessions /usr/local/bin \
  /usr/local/share/applications
sudo install -m 0755 "$ROOT/scripts/start-apollo.sh" "$SHARE_DIR/scripts/start-apollo.sh"
sudo install -m 0755 "$ROOT/scripts/apollo-session" "$BIN_WRAPPER"
sudo install -m 0755 "$ROOT/scripts/apollo-lock.sh" "$SHARE_DIR/scripts/apollo-lock.sh"
sudo install -m 0755 "$ROOT/scripts/apollo-logout.sh" "$SHARE_DIR/scripts/apollo-logout.sh"
sudo install -m 0755 "$ROOT/scripts/apollo-theme-nt.sh" "$SHARE_DIR/scripts/apollo-theme-nt.sh"
sudo install -m 0755 "$ROOT/scripts/apollo-theme-nt.sh" /usr/local/bin/apollo-theme-nt
sudo install -m 0644 "$ROOT/session/apollo.desktop" "$DESKTOP_DST"
sudo install -m 0644 "$ROOT/session/apollo-lock.desktop" /usr/local/share/applications/apollo-lock.desktop
sudo install -m 0644 "$ROOT/session/apollo-logout.desktop" /usr/local/share/applications/apollo-logout.desktop
sudo install -m 0644 "$ROOT/session/apollo-screenshot-region.desktop" /usr/local/share/applications/apollo-screenshot-region.desktop
sudo install -m 0644 "$ROOT/session/apollo-screenshot-full.desktop" /usr/local/share/applications/apollo-screenshot-full.desktop
USER_APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$USER_APP_DIR"
install -m 0644 "$ROOT/session/apollo-lock.desktop" "$USER_APP_DIR/apollo-lock.desktop"
install -m 0644 "$ROOT/session/apollo-logout.desktop" "$USER_APP_DIR/apollo-logout.desktop"
install -m 0644 "$ROOT/session/apollo-screenshot-region.desktop" "$USER_APP_DIR/apollo-screenshot-region.desktop"
install -m 0644 "$ROOT/session/apollo-screenshot-full.desktop" "$USER_APP_DIR/apollo-screenshot-full.desktop"

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


# --- global shortcuts (Super+Q close, Super+T kitty, Super+C screenshots) ---
KGSRC="${XDG_CONFIG_HOME:-$HOME/.config}/kglobalshortcutsrc"
KGSNIP="$ROOT/config/kglobalshortcutsrc.snippet"
if [[ -f "$KGSNIP" ]]; then
  mkdir -p "$(dirname "$KGSRC")"
  if [[ ! -f "$KGSRC" ]]; then
    install -m 0644 "$KGSNIP" "$KGSRC"
    info "wrote $KGSRC (Meta+Q close, Meta+T kitty, Meta+Shift+T tiles, Meta+L lock, Meta+Shift+L logout, Meta+C region, Meta+Shift+C fullscreen)"
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
    if ! grep -q '\[services\]\[apollo-lock.desktop\]' "$KGSRC"; then
      printf '\n[services][apollo-lock.desktop]\n_k_friendly_name=Lock Session\n_launch=Meta+L,none,Lock Session\n' >> "$KGSRC"
    else
      sed -i '/\[services\]\[apollo-lock.desktop\]/,/^\[/{s/^_launch=.*/_launch=Meta+L,none,Lock Session/;}' "$KGSRC" || true
    fi
    if ! grep -q '\[services\]\[apollo-logout.desktop\]' "$KGSRC"; then
      printf '\n[services][apollo-logout.desktop]\n_k_friendly_name=Log Out\n_launch=Meta+Shift+L,none,Log Out\n' >> "$KGSRC"
    else
      sed -i '/\[services\]\[apollo-logout.desktop\]/,/^\[/{s/^_launch=.*/_launch=Meta+Shift+L,none,Log Out/;}' "$KGSRC" || true
    fi
    if ! grep -q '\[services\]\[apollo-screenshot-region.desktop\]' "$KGSRC"; then
      printf '\n[services][apollo-screenshot-region.desktop]\n_k_friendly_name=Capture Region\n_launch=Meta+C,none,Capture Region\n' >> "$KGSRC"
    else
      sed -i '/\[services\]\[apollo-screenshot-region.desktop\]/,/^\[/{s/^_launch=.*/_launch=Meta+C,none,Capture Region/;}' "$KGSRC" || true
    fi
    if ! grep -q '\[services\]\[apollo-screenshot-full.desktop\]' "$KGSRC"; then
      printf '\n[services][apollo-screenshot-full.desktop]\n_k_friendly_name=Capture Full Screen\n_launch=Meta+Shift+C,none,Capture Full Screen\n' >> "$KGSRC"
    else
      sed -i '/\[services\]\[apollo-screenshot-full.desktop\]/,/^\[/{s/^_launch=.*/_launch=Meta+Shift+C,none,Capture Full Screen/;}' "$KGSRC" || true
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

FCITX_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fcitx5"
if [[ ! -e "$FCITX_DIR/profile" ]]; then
  mkdir -p "$FCITX_DIR"
  install -m 0644 "$ROOT/config/fcitx5/profile" "$FCITX_DIR/profile"
  info "wrote $FCITX_DIR/profile (Sucheng Quick3 + Mozc)"
else
  info "keep existing $FCITX_DIR/profile"
fi

# Assets first, so a new kwinrc never points at a missing Aurorae theme.
info "installing NT Legacy 98 (win98 / win98-nacht) assets..."
"$ROOT/scripts/apollo-theme-nt.sh" fetch

KWINRC="${XDG_CONFIG_HOME:-$HOME/.config}/kwinrc"
kwin_created=0
mkdir -p "$(dirname "$KWINRC")"
if [[ ! -f "$KWINRC" ]]; then
  install -m 0644 "$ROOT/config/kwin/kwinrc.snippet" "$KWINRC"
  kwin_created=1
  info "wrote $KWINRC"
else
  info "keep existing $KWINRC (not overwriting)"
fi

NT_APPLIED="${XDG_DATA_HOME:-$HOME/.local/share}/apollo/nt-legacy/applied"
if [[ ! -f "$NT_APPLIED" ]]; then
  info "applying NT Legacy 98 day theme"
  "$ROOT/scripts/apollo-theme-nt.sh" day
elif [[ "$kwin_created" -eq 1 ]]; then
  nt_variant="$(<"$NT_APPLIED")"
  case "$nt_variant" in
    day|night)
      info "restoring NT Legacy variant ($nt_variant) into new kwinrc"
      "$ROOT/scripts/apollo-theme-nt.sh" "$nt_variant"
      ;;
    *)
      warn "invalid NT Legacy marker ($nt_variant); applying day"
      "$ROOT/scripts/apollo-theme-nt.sh" day
      ;;
  esac
else
  info "NT Legacy variant already chosen ($(<"$NT_APPLIED")); not switching"
fi
"$ROOT/scripts/apollo-theme-nt.sh" ensure-file-manager

# --- services ---
info "enabling NetworkManager, bluetooth, greetd..."
sudo systemctl enable NetworkManager.service || warn "could not enable NetworkManager"
sudo systemctl enable bluetooth.service || warn "could not enable bluetooth"
sudo systemctl enable greetd.service

cat <<DONE

============================================================
Apollo install finished.

Installed / configured:
  - Apollo DE: KWin + Quickshell + NT Legacy 98 (no plasmashell)
  - pcmanfm-qt (file manager), pavucontrol-qt (volume mixer)
  - theme switch: apollo-theme-nt day | night | toggle | status
  - NVIDIA: nvidia-open + nvidia-utils + libva-nvidia-driver
  - greetd autologin as ${INSTALL_USER} (NO greeter / NO tuigreet / NO SDDM)
  - fish as login shell for ${INSTALL_USER}
  - kitty, yazi, neovim + LazyVim starter
  - fonts: IBM Plex OTF, Noroshi Code, Apple Color Emoji, Symbols Nerd Font
  - awww wallpaper daemon (random image from ~/Pictures/wallpapers/)
  - fcitx5: Sucheng (Quick3) + Mozc romaji
  - Super+L lock, Super+Shift+L log out
  - Spectacle: Super+C region, Super+Shift+C full screen
  - cliphist + wl-clip-persist (clipboard history; regular clipboard survives app exit)
  - NetworkManager + BlueZ

Next:
  1) reboot → should land in Apollo automatically
  2) wallpapers: ~/Pictures/wallpapers/ (awww picks one at login)
  3) edit shell:  ~/.config/quickshell/apollo/shell.qml
  4) edit kwin:   ~/.config/kwinrc
  5) theme:      apollo-theme-nt day | night | toggle
     Aurorae title bars load when KWin starts. Log out once if the frame stays old.
     Volume: pavucontrol-qt   Files: pcmanfm-qt

NVIDIA:
  - modeset comes from Arch's nvidia-utils; egl-wayland is a dep of nvidia-utils

apollod:
  - Planned Go daemon for your unified settings center
    (Wi-Fi, Bluetooth, monitors, Quickshell look/feel, keybinds, exec).
  - Not installed yet; start-apollo.sh launches it when on PATH.

Re-run safely: ./install.sh  (existing user configs are kept)
============================================================
DONE

#!/usr/bin/env bash
# Apollo — NT Legacy 98（日間 win98、夜間 win98-nacht）
#
# 一次過寫入標題列（Aurorae）、色彩方案、圖示及 Qt 的 Windows widget style。
# 不安裝 Plasma 面板、Global Theme、GRUB 或 Plymouth。Quickshell 日後可呼叫
# toggle；此腳本不加入按鈕。Aurorae 標題列在 KWin 啟動時載入；若框未變，請登出一次。
#
# English: install and switch the upstream NT Legacy win98 / win98-nacht pair
# from https://github.com/huppiflupp/plasma-theme-lab (folder nt-legacy/).
# Day and night always write the same layers together. There is no plasmashell,
# panel layout, or look-and-feel package here.
#
#   apollo-theme-nt day|night|toggle|status|fetch|ensure-file-manager
set -euo pipefail

NT_REPO="https://github.com/huppiflupp/plasma-theme-lab.git"
LOG_PREFIX="[apollo-theme-nt]"

DAY_DIR="NTLegacyWin98"
NIGHT_DIR="NTLegacyWin98Nacht"
DAY_DECO="__aurorae__svg__NTLegacyWin98"
NIGHT_DECO="__aurorae__svg__NTLegacyWin98Nacht"
DAY_COLOR="NTLegacyWin98"
NIGHT_COLOR="NTLegacyWin98Nacht"
DAY_ICONS="NTLegacyIcons"
NIGHT_ICONS="NTLegacyIconsNacht"
WIDGET_STYLE="Windows"
AURORAE_LIBRARY="org.kde.kwin.aurorae"
FILE_MANAGER_DESKTOP="pcmanfm-qt.desktop"

cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
kwinrc="$cfg/kwinrc"
kdeglobals="$cfg/kdeglobals"
pcmanfm_conf="$cfg/pcmanfm-qt/default/settings.conf"
mimeapps="$cfg/mimeapps.list"
marker="$data/apollo/nt-legacy/applied"
stamp="$data/apollo/nt-legacy/.apollo-source"

info() { printf '%s %s\n' "$LOG_PREFIX" "$*" >&2; }
die()  { printf '%s error: %s\n' "$LOG_PREFIX" "$*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
Usage: apollo-theme-nt <command>

  day                   NT Legacy 98（日間）
  night                 NT Legacy 98 Night（夜間）
  toggle                日間與夜間對調；未知或混雜狀態改為日間
  status                印出目前各層（供日後 Quickshell 讀取）
  fetch                 由上游下載 win98 與 win98-nacht 資產
  ensure-file-manager   若尚未指定檔案總管，將 inode/directory 設為 pcmanfm-qt

日與夜會同時寫入 Aurorae、色彩方案、圖示及 widgetStyle=Windows。
標題列若未更換，請登出再登入。已開啟的 Qt 程式可能要重新開啟。

English:
  day|night|toggle keep the title bar, colour scheme, icons, and the Qt
  Windows widget style in one step. status prints key=value lines.
  fetch installs only Aurorae, .colors, and icons (night icons are derived
  here). Plasma panels, Global Theme, GRUB, and Plymouth are not installed.
  Aurorae frames load when KWin starts; log out once if the frame stays old.
EOF
}

read_ini() {
  local file="$1" section="$2" key="$3"
  [[ -f "$file" ]] || return 0
  awk -v section="$section" -v key="$key" '
    /^\[/ {
      in_section = ($0 == "[" section "]")
      next
    }
    in_section && index($0, key "=") == 1 {
      print substr($0, length(key) + 2)
      exit
    }
  ' "$file"
}

set_ini() {
  local file="$1" section="$2" key="$3" value="$4"
  local dir tmp
  dir="$(dirname "$file")"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.apollo-ini.XXXXXX")"
  if [[ -f "$file" ]]; then
    awk -v section="$section" -v key="$key" -v value="$value" '
      BEGIN { in_section = 0; found_section = 0; written = 0 }
      /^\[/ {
        if (in_section && !written) {
          print key "=" value
          written = 1
        }
        in_section = ($0 == "[" section "]")
        if (in_section) found_section = 1
      }
      in_section && index($0, key "=") == 1 {
        print key "=" value
        written = 1
        next
      }
      { print }
      END {
        if (!found_section) {
          if (NR > 0) print ""
          print "[" section "]"
          print key "=" value
        } else if (!written) {
          print key "=" value
        }
      }
    ' "$file" >"$tmp"
  else
    printf '[%s]\n%s=%s\n' "$section" "$key" "$value" >"$tmp"
  fi
  chmod 0644 "$tmp"
  mv -f "$tmp" "$file"
}

assets_ready() {
  [[ -f "$data/aurorae/themes/$DAY_DIR/metadata.desktop" ]] \
    && [[ -f "$data/aurorae/themes/$NIGHT_DIR/metadata.desktop" ]] \
    && [[ -f "$data/color-schemes/$DAY_COLOR.colors" ]] \
    && [[ -f "$data/color-schemes/$NIGHT_COLOR.colors" ]] \
    && [[ -f "$data/icons/$DAY_ICONS/index.theme" ]] \
    && [[ -f "$data/icons/$NIGHT_ICONS/index.theme" ]]
}

require_assets() {
  if assets_ready; then
    return 0
  fi
  die "NT Legacy 98 assets are missing. Run: apollo-theme-nt fetch   or   ./install.sh"
}

with_lock() {
  mkdir -p "$data/apollo/nt-legacy"
  exec 9>>"$data/apollo/nt-legacy/apply.lock"
  if command -v flock >/dev/null 2>&1; then
    flock 9
  else
    info "flock not found; continuing without a lock"
  fi
}

make_night_icons() {
  local src="$1" dst="$2" tmp
  rm -rf "$dst"
  cp -a "$src" "$dst"
  tmp="$(mktemp)"
  # Same images as the day set. Only the fallback chain changes: an icon
  # theme has one Inherits line, and walking NTLegacyIcons would reach
  # breeze before breeze-dark. Upstream does this in tools/make-night-icons.py;
  # the night set is not stored in the git tree.
  if ! awk '
    BEGIN { inherits = 0; name = 0; comment = 0 }
    /^Inherits=breeze,hicolor$/ {
      print "Inherits=breeze-dark,breeze,hicolor"
      inherits = 1
      next
    }
    /^Name=NT Legacy Icons$/ {
      print "Name=NT Legacy Icons Night"
      name = 1
      next
    }
    /^Comment=Icons in the style of Windows NT 4.0, fully generated$/ {
      print "Comment=Icons in the style of Windows NT 4.0, fully generated - version for the dark variants"
      comment = 1
      next
    }
    { print }
    END {
      if (!inherits || !name || !comment) exit 1
    }
  ' "$dst/index.theme" >"$tmp"; then
    rm -f "$tmp"
    rm -rf "$dst"
    die "could not derive $NIGHT_ICONS (upstream index.theme changed)"
  fi
  mv -f "$tmp" "$dst/index.theme"
  chmod 0644 "$dst/index.theme"
}

refresh_icon_cache() {
  local set
  if ! command -v gtk-update-icon-cache >/dev/null 2>&1; then
    return 0
  fi
  for set in "$DAY_ICONS" "$NIGHT_ICONS"; do
    gtk-update-icon-cache -q -t -f "$data/icons/$set" >/dev/null 2>&1 || true
  done
}

cmd_fetch() {
  local rev src tmp
  command -v git >/dev/null 2>&1 || die "missing command: git"
  rev="$(GIT_TERMINAL_PROMPT=0 git ls-remote "$NT_REPO" HEAD | awk 'NR==1 { print $1 }')"
  [[ -n "$rev" ]] || die "could not resolve NT Legacy HEAD"
  if [[ -f "$stamp" && "$(<"$stamp")" == "$rev" ]] && assets_ready; then
    info "NT Legacy 98 assets already present ($rev)"
    return 0
  fi

  info "fetching NT Legacy 98 assets from GitHub..."
  (
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 --filter=blob:none --sparse \
      "$NT_REPO" "$tmp/theme"
    git -C "$tmp/theme" sparse-checkout set --no-cone \
      /nt-legacy/aurorae/NTLegacyWin98/ \
      /nt-legacy/aurorae/NTLegacyWin98Nacht/ \
      /nt-legacy/color-schemes/NTLegacyWin98.colors \
      /nt-legacy/color-schemes/NTLegacyWin98Nacht.colors \
      /nt-legacy/icons-nt/NTLegacyIcons/ \
      /nt-legacy/LICENSE \
      /nt-legacy/ATTRIBUTION.md
    src="$tmp/theme/nt-legacy"
    [[ -f "$src/aurorae/$DAY_DIR/metadata.desktop" ]] || die "sparse checkout missed $DAY_DIR"
    [[ -f "$src/aurorae/$NIGHT_DIR/metadata.desktop" ]] || die "sparse checkout missed $NIGHT_DIR"
    [[ -f "$src/color-schemes/$DAY_COLOR.colors" ]] || die "sparse checkout missed $DAY_COLOR.colors"
    [[ -f "$src/color-schemes/$NIGHT_COLOR.colors" ]] || die "sparse checkout missed $NIGHT_COLOR.colors"
    [[ -f "$src/icons-nt/$DAY_ICONS/index.theme" ]] || die "sparse checkout missed $DAY_ICONS"
    grep -qx "X-KDE-PluginInfo-Name=$DAY_DECO" "$src/aurorae/$DAY_DIR/metadata.desktop" \
      || die "unexpected Aurorae id in $DAY_DIR"
    grep -qx "X-KDE-PluginInfo-Name=$NIGHT_DECO" "$src/aurorae/$NIGHT_DIR/metadata.desktop" \
      || die "unexpected Aurorae id in $NIGHT_DIR"

    mkdir -p "$data/aurorae/themes" "$data/color-schemes" "$data/icons" "$data/apollo/nt-legacy"
    rm -rf "$data/aurorae/themes/$DAY_DIR" "$data/aurorae/themes/$NIGHT_DIR"
    cp -a "$src/aurorae/$DAY_DIR" "$src/aurorae/$NIGHT_DIR" "$data/aurorae/themes/"
    install -m 0644 "$src/color-schemes/$DAY_COLOR.colors" "$data/color-schemes/$DAY_COLOR.colors"
    install -m 0644 "$src/color-schemes/$NIGHT_COLOR.colors" "$data/color-schemes/$NIGHT_COLOR.colors"
    rm -rf "$data/icons/$DAY_ICONS" "$data/icons/$NIGHT_ICONS"
    cp -a "$src/icons-nt/$DAY_ICONS" "$data/icons/$DAY_ICONS"
    make_night_icons "$data/icons/$DAY_ICONS" "$data/icons/$NIGHT_ICONS"
    install -m 0644 "$src/LICENSE" "$data/apollo/nt-legacy/LICENSE"
    if [[ -f "$src/ATTRIBUTION.md" ]]; then
      install -m 0644 "$src/ATTRIBUTION.md" "$data/apollo/nt-legacy/ATTRIBUTION.md"
    fi
    cat >"$data/apollo/nt-legacy/SOURCE" <<EOF
source=$NT_REPO
path=nt-legacy
commit=$rev
variants=win98 win98-nacht
layers=aurorae color-schemes icons
widget_style=$WIDGET_STYLE
omitted=desktoptheme look-and-feel panel grub plymouth cursors konsole wallpapers
license=GPL-2.0-or-later
EOF
    chmod 0644 "$data/apollo/nt-legacy/SOURCE"
    assets_ready || die "NT Legacy install did not produce the expected files"
    grep -qx 'Inherits=breeze-dark,breeze,hicolor' "$data/icons/$NIGHT_ICONS/index.theme" \
      || die "night icon theme was not derived"
    printf '%s\n' "$rev" >"$stamp"
  )
  refresh_icon_cache
  info "installed NT Legacy 98 assets ($rev)"
  info "omitted on purpose: Plasma panel, Global Theme, desktop theme, GRUB, Plymouth, cursors"
}

notify_session() {
  local cache signal
  if [[ "${APOLLO_NT_SKIP_NOTIFY:-}" == 1 ]]; then
    return 0
  fi
  cache="${XDG_CACHE_HOME:-$HOME/.cache}"
  rm -f "$cache/icon-cache.kcache" || true

  # KWin reloads decoration settings here. Upstream NT Legacy still finds that
  # the Aurorae SVG theme itself is loaded only at session start.
  if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  elif command -v qdbus >/dev/null 2>&1; then
    qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  fi
  if command -v dbus-send >/dev/null 2>&1; then
    # KGlobalSettings change types still honoured by plasma-integration:
    # 0 palette, 2 widget style, 3 settings, 4 icons.
    for signal in 0 2 3 4; do
      dbus-send --session --type=signal /KGlobalSettings \
        org.kde.KGlobalSettings.notifyChange "int32:${signal}" int32:0 \
        >/dev/null 2>&1 || true
    done
  fi
}

cmd_apply() {
  local which="$1" dir deco color icons
  require_assets
  case "$which" in
    day)
      dir="$DAY_DIR"
      deco="$DAY_DECO"
      color="$DAY_COLOR"
      icons="$DAY_ICONS"
      ;;
    night)
      dir="$NIGHT_DIR"
      deco="$NIGHT_DECO"
      color="$NIGHT_COLOR"
      icons="$NIGHT_ICONS"
      ;;
    *)
      die "unknown variant: $which"
      ;;
  esac
  grep -qx "X-KDE-PluginInfo-Name=$deco" "$data/aurorae/themes/$dir/metadata.desktop" \
    || die "Aurorae metadata for $dir does not name $deco"
  if [[ "$which" == "night" ]]; then
    grep -qx 'Inherits=breeze-dark,breeze,hicolor' "$data/icons/$NIGHT_ICONS/index.theme" \
      || die "$NIGHT_ICONS is missing the breeze-dark fallback; run fetch again"
  else
    grep -qx 'Inherits=breeze,hicolor' "$data/icons/$DAY_ICONS/index.theme" \
      || die "$DAY_ICONS is missing the breeze fallback; run fetch again"
  fi

  # Write every layer before notifying, so a running session never sees a
  # day frame with a night palette.
  set_ini "$kwinrc" org.kde.kdecoration2 library "$AURORAE_LIBRARY"
  set_ini "$kwinrc" org.kde.kdecoration2 theme "$deco"
  set_ini "$kdeglobals" General ColorScheme "$color"
  set_ini "$kdeglobals" KDE widgetStyle "$WIDGET_STYLE"
  set_ini "$kdeglobals" Icons Theme "$icons"
  set_ini "$pcmanfm_conf" System IconThemeName "$icons"
  set_ini "$pcmanfm_conf" System FallbackIconThemeName "$icons"
  mkdir -p "$(dirname "$marker")"
  printf '%s\n' "$which" >"$marker"

  notify_session
  info "applied $which ($color)"
  info "Aurorae title bars load when KWin starts. If the frame did not change, log out and back in once."
  info "Qt apps that are already open may need a restart for colours, icons, and the Windows widget style."
  cmd_status
}

layers_match() {
  local deco="$1" color="$2" icons="$3"
  [[ "$(read_ini "$kwinrc" org.kde.kdecoration2 library)" == "$AURORAE_LIBRARY" ]] \
    && [[ "$(read_ini "$kwinrc" org.kde.kdecoration2 theme)" == "$deco" ]] \
    && [[ "$(read_ini "$kdeglobals" General ColorScheme)" == "$color" ]] \
    && [[ "$(read_ini "$kdeglobals" Icons Theme)" == "$icons" ]] \
    && [[ "$(read_ini "$kdeglobals" KDE widgetStyle)" == "$WIDGET_STYLE" ]]
}

pcmanfm_matches() {
  local icons="$1"
  [[ ! -f "$pcmanfm_conf" ]] && return 0
  [[ "$(read_ini "$pcmanfm_conf" System IconThemeName)" == "$icons" ]] \
    && [[ "$(read_ini "$pcmanfm_conf" System FallbackIconThemeName)" == "$icons" ]]
}

cmd_status() {
  local kind="unset" coherent="no"
  local dec lib col ico sty pcm pcm_fb
  dec="$(read_ini "$kwinrc" org.kde.kdecoration2 theme)"
  lib="$(read_ini "$kwinrc" org.kde.kdecoration2 library)"
  col="$(read_ini "$kdeglobals" General ColorScheme)"
  ico="$(read_ini "$kdeglobals" Icons Theme)"
  sty="$(read_ini "$kdeglobals" KDE widgetStyle)"
  pcm="$(read_ini "$pcmanfm_conf" System IconThemeName)"
  pcm_fb="$(read_ini "$pcmanfm_conf" System FallbackIconThemeName)"

  if layers_match "$DAY_DECO" "$DAY_COLOR" "$DAY_ICONS" && pcmanfm_matches "$DAY_ICONS"; then
    kind="day"
    coherent="yes"
  elif layers_match "$NIGHT_DECO" "$NIGHT_COLOR" "$NIGHT_ICONS" && pcmanfm_matches "$NIGHT_ICONS"; then
    kind="night"
    coherent="yes"
  elif [[ -n "$dec$lib$col$ico$sty$pcm$pcm_fb" ]]; then
    kind="mixed"
  fi

  printf 'variant=%s\n' "$kind"
  printf 'coherent=%s\n' "$coherent"
  printf 'decoration=%s\n' "$dec"
  printf 'decoration_library=%s\n' "$lib"
  printf 'color_scheme=%s\n' "$col"
  printf 'icons=%s\n' "$ico"
  printf 'widget_style=%s\n' "$sty"
  printf 'pcmanfm_icons=%s\n' "$pcm"
  printf 'pcmanfm_fallback_icons=%s\n' "$pcm_fb"
}

cmd_toggle() {
  if [[ "$(cmd_status | awk -F= '$1 == "variant" { print $2 }')" == "day" ]]; then
    cmd_apply night
  else
    cmd_apply day
  fi
}

cmd_ensure_file_manager() {
  local current
  current="$(read_ini "$mimeapps" "Default Applications" inode/directory)"
  if [[ -n "$current" ]]; then
    info "kept existing inode/directory handler: $current"
    info "Not changed. Set inode/directory=$FILE_MANAGER_DESKTOP in $mimeapps to use PCManFM-Qt."
    printf 'inode/directory=%s\nchanged=no\n' "$current"
    return 0
  fi
  set_ini "$mimeapps" "Default Applications" inode/directory "$FILE_MANAGER_DESKTOP"
  info "set inode/directory=$FILE_MANAGER_DESKTOP"
  info "Revert: delete that line under [Default Applications] in $mimeapps."
  printf 'inode/directory=%s\nchanged=yes\n' "$FILE_MANAGER_DESKTOP"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    -h|--help|help|"")
      usage
      [[ -n "$cmd" && "$cmd" != "" ]] || exit 2
      exit 0
      ;;
    day|night)
      with_lock
      cmd_apply "$cmd"
      ;;
    toggle)
      with_lock
      cmd_toggle
      ;;
    status)
      cmd_status
      ;;
    fetch)
      with_lock
      cmd_fetch
      ;;
    ensure-file-manager)
      with_lock
      cmd_ensure_file_manager
      ;;
    *)
      usage
      die "unknown command: $cmd"
      ;;
  esac
}

main "$@"

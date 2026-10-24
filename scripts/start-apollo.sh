#!/usr/bin/env bash
# Apollo session: KWin + Quickshell (no plasmashell).
set -euo pipefail

export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Apollo:KDE}"
export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-Apollo}"
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
export QT_WAYLAND_DISABLE_WINDOWDECORATION=0

# NVIDIA Wayland helpers (harmless on non-NVIDIA if libs absent)
export GBM_BACKEND="${GBM_BACKEND:-nvidia-drm}"
export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"
export __NV_PRIME_RENDER_OFFLOAD="${__NV_PRIME_RENDER_OFFLOAD:-1}"
export LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-nvidia}"

# Polkit agent (GUI auth prompts)
if [[ -x /usr/lib/polkit-kde-authentication-agent-1 ]]; then
  /usr/lib/polkit-kde-authentication-agent-1 &
elif [[ -x /usr/lib/polkit-kde-agent-1 ]]; then
  /usr/lib/polkit-kde-agent-1 &
fi

# apollod = unified settings center daemon (Wi-Fi/BT/monitors/look/keybinds/exec)
if command -v apollod >/dev/null 2>&1; then
  apollod &
elif command -v universed >/dev/null 2>&1; then
  # temporary alias while the daemon is renamed
  universed &
fi

# Wallpaper (awww, the successor of swww). KWin is exec'd below, so the daemon
# waits for its Wayland socket in the background. Missing images or an awww
# failure must not abort the session.
start_awww_wallpaper() {
  if ! command -v awww-daemon >/dev/null 2>&1 || ! command -v awww >/dev/null 2>&1; then
    echo "warning: awww not found; skipping wallpaper" >&2
    return 0
  fi

  local dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/wallpapers"
  if [[ ! -d "$dir" ]]; then
    echo "warning: wallpaper directory missing ($dir); skipping" >&2
    return 0
  fi

  local -a images=()
  local f
  while IFS= read -r -d '' f; do
    images+=("$f")
  done < <(find "$dir" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' \) \
    -print0 2>/dev/null || true)

  if [[ ${#images[@]} -eq 0 ]]; then
    echo "warning: no wallpapers in $dir; skipping" >&2
    return 0
  fi

  local picked="${images[$((RANDOM % ${#images[@]}))]}"
  # KWin creates the Wayland socket when it is exec'd, so wait for it here.
  (
    local runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    local sock display="" i ready=0
    for i in {1..50}; do
      if [[ -n "${WAYLAND_DISPLAY:-}" && -S "$runtime/$WAYLAND_DISPLAY" ]]; then
        display="$WAYLAND_DISPLAY"
        break
      fi
      sock="$(find "$runtime" -maxdepth 1 -type s -name 'wayland-*' -print -quit 2>/dev/null || true)"
      if [[ -n "$sock" ]]; then
        display="$(basename "$sock")"
        break
      fi
      sleep 0.1
    done
    if [[ -z "$display" ]]; then
      echo "warning: Wayland display not ready; skipping wallpaper" >&2
      exit 0
    fi
    export WAYLAND_DISPLAY="$display"
    if ! command -v pgrep >/dev/null 2>&1 || ! pgrep -x awww-daemon >/dev/null 2>&1; then
      awww-daemon &
    fi
    for i in {1..25}; do
      if awww query >/dev/null 2>&1; then
        ready=1
        break
      fi
      sleep 0.2
    done
    if [[ "$ready" -ne 1 ]]; then
      echo "warning: awww-daemon not ready; skipping wallpaper" >&2
      exit 0
    fi
    awww img "$picked" || echo "warning: awww img failed for $picked" >&2
  ) &
  return 0
}

start_awww_wallpaper || echo "warning: wallpaper setup failed" >&2

# Shell UI (config name = folder under ~/.config/quickshell/)
if command -v quickshell >/dev/null 2>&1; then
  quickshell apollo &
else
  echo "warning: quickshell not found; starting KWin only" >&2
fi

exec kwin_wayland

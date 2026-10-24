#!/usr/bin/env bash
# Minimal KWin + Quickshell session starter (no plasmashell).
set -euo pipefail

export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Universe:KDE}"
export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-Universe}"
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
export QT_WAYLAND_DISABLE_WINDOWDECORATION=0

# NVIDIA Wayland helpers (harmless on non-NVIDIA if libs absent)
export GBM_BACKEND="${GBM_BACKEND:-nvidia-drm}"
export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"
export __NV_PRIME_RENDER_OFFLOAD="${__NV_PRIME_RENDER_OFFLOAD:-1}"

# Polkit agent (GUI auth prompts)
if [[ -x /usr/lib/polkit-kde-authentication-agent-1 ]]; then
  /usr/lib/polkit-kde-authentication-agent-1 &
elif [[ -x /usr/lib/polkit-kde-agent-1 ]]; then
  /usr/lib/polkit-kde-agent-1 &
fi

# universed = your unified settings center daemon (Wi-Fi/BT/monitors/look/keybinds/exec)
if command -v universed >/dev/null 2>&1; then
  universed &
fi

# Shell UI (config name = folder under ~/.config/quickshell/)
if command -v quickshell >/dev/null 2>&1; then
  quickshell universe &
else
  echo "warning: quickshell not found; starting KWin only" >&2
fi

# Compositor is the session leader
exec kwin_wayland

#!/usr/bin/env bash
# End this Apollo session. greetd returns to tuigreet afterwards.
set -u

sid="${XDG_SESSION_ID:-}"
if [[ -z "$sid" ]] && command -v loginctl >/dev/null 2>&1; then
  sid="$(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$(id -un)" '$3==u { print $1; exit }')"
fi

if [[ -n "$sid" ]] && command -v loginctl >/dev/null 2>&1; then
  exec loginctl terminate-session "$sid"
fi

echo "warning: no logind session id; stopping kwin_wayland" >&2
if command -v pkill >/dev/null 2>&1; then
  pkill -x kwin_wayland || true
fi
exit 0

#!/usr/bin/env bash
# APOLLO_KSCREENLOCKER_GREET_WRAPPER
# KWin execs this in place of /usr/lib/kscreenlocker_greet.
# The session keeps QT_IM_MODULE=fcitx (Sucheng / Mozc). This process does not:
# that module eats the password field (KDE bug 306932), and the seeded profile
# defaults to Quick3, which never commits ASCII while the candidate window
# cannot show on the lock screen. Qt's compose module passes normal keys
# through and does not open a Wayland text-input context.
# Exit 1 if the real binary is missing. A script that starts and then fails
# stays locked (KWin retries, then the emergency greeter). A missing exec
# would be FailedToStart, and KWin unlocks without a password.
set -u

unset GTK_IM_MODULE
unset QT_IM_MODULES
unset SDL_IM_MODULE
unset XMODIFIERS
unset GLFW_IM_MODULE
export QT_IM_MODULE=compose

real="${APOLLO_GREET_REAL:-}"
# KWin execs the greet path. That path is this wrapper, so $0 is
# /usr/lib/kscreenlocker_greet and the saved binary is beside it.
if [[ -z "$real" && -n "${0:-}" && -x "${0}.apollo-real" && ! -L "${0}.apollo-real" ]]; then
  real="${0}.apollo-real"
fi
if [[ -z "$real" ]]; then
  for candidate in \
    /usr/lib/kscreenlocker_greet.apollo-real \
    /usr/libexec/kscreenlocker_greet.apollo-real
  do
    if [[ -x "$candidate" && ! -L "$candidate" ]]; then
      real="$candidate"
      break
    fi
  done
fi

if [[ -z "$real" || ! -x "$real" || -L "$real" ]]; then
  echo "apollo: lock greeter binary missing (${real:-kscreenlocker_greet.apollo-real})" >&2
  exit 1
fi
if head -n 15 "$real" | grep -q 'APOLLO_KSCREENLOCKER_GREET_WRAPPER'; then
  echo "apollo: refusing to exec the wrapper as the greeter ($real)" >&2
  exit 1
fi

exec "$real" "$@"

#!/usr/bin/env bash
# APOLLO_KSCREENLOCKER_GREET_WRAPPER
# KWin execs this in place of /usr/lib/kscreenlocker_greet.
# The session keeps QT_IM_MODULE=fcitx (Sucheng / Mozc). This process does not:
# that module eats the password field (KDE bug 306932). It also selects the
# Apollo lock screen. The built-in fallback answers PAM before the prompt is
# stored, so a typed password never unlocks.
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

# Apollo does not install the plasma-desktop shell, so the greeter would load
# its built-in fallback. That theme answers the secret prompt before the
# pending D-Bus message exists, and the password never reaches PAM.
# PLASMA_DEFAULT_SHELL is only the default when plasmashellrc has no
# ShellPackage key, so this process gets an empty config directory.
export PLASMA_DEFAULT_SHELL="${APOLLO_LOCK_SHELL:-org.kde.apollo}"
greeter_config="${XDG_RUNTIME_DIR:-/tmp}/apollo-greeter-config"
if mkdir -p "$greeter_config"; then
  export XDG_CONFIG_HOME="$greeter_config"
else
  echo "apollo: could not isolate greeter config ($greeter_config)" >&2
fi

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

#!/usr/bin/env bash
# Lock the Apollo session without plasmashell.
# KWin handles logind's lock signal when kscreenlocker is installed.
# The greeter is a child of KWin, not of this script. The wrapper selects the
# Apollo lock screen and compose input for that process only.
set -u

locked=0
if [[ -n "${XDG_SESSION_ID:-}" ]] && command -v loginctl >/dev/null 2>&1; then
  loginctl lock-session "$XDG_SESSION_ID" && locked=1
fi

if command -v dbus-send >/dev/null 2>&1; then
  dbus-send --session --print-reply --dest=org.freedesktop.ScreenSaver \
    /ScreenSaver org.freedesktop.ScreenSaver.Lock >/dev/null && locked=1
  dbus-send --session --print-reply --dest=org.freedesktop.ScreenSaver \
    /org/freedesktop/ScreenSaver org.freedesktop.ScreenSaver.Lock >/dev/null && locked=1
  dbus-send --session --print-reply --dest=org.kde.screensaver \
    /ScreenSaver org.kde.screensaver.Lock >/dev/null && locked=1
  dbus-send --session --print-reply --dest=org.kde.screensaver \
    /org/kde/screensaver org.kde.screensaver.Lock >/dev/null && locked=1
fi

if command -v qdbus6 >/dev/null 2>&1; then
  qdbus6 org.freedesktop.ScreenSaver /ScreenSaver Lock && locked=1
  qdbus6 org.kde.screensaver /ScreenSaver Lock && locked=1
fi

if [[ "$locked" -ne 1 ]]; then
  echo "warning: could not lock the session" >&2
fi
exit 0

#!/usr/bin/env bash
# Pacman hook: kscreenlocker was removed. Drop the saved greeter binary and
# an Apollo-owned /etc/pam.d/kde so a later package file is not shadowed.
set -euo pipefail

log() { printf '[apollo] %s\n' "$*"; }

etc_file="${APOLLO_PAM_ETC:-/etc/pam.d}/kde"
rm -f \
  "${APOLLO_GREET_REAL_LIB:-/usr/lib/kscreenlocker_greet.apollo-real}" \
  "${APOLLO_GREET_REAL_LIBEXEC:-/usr/libexec/kscreenlocker_greet.apollo-real}"

if [[ -f "$etc_file" ]] && grep -q 'APOLLO_KSCREENLOCKER_PAM' "$etc_file"; then
  rm -f "$etc_file"
  log "removed Apollo PAM fallback $etc_file"
fi

log "removed kscreenlocker greeter wrapper leftovers"

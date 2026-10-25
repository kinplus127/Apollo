#!/usr/bin/env bash
# PAM service "kde", the Apollo lock-screen package, and the greeter wrapper.
# Called from install.sh and from the pacman hook after kscreenlocker
# is installed or upgraded. One sudo invocation in install.sh covers this.
set -euo pipefail

log() { printf '[apollo] %s\n' "$*"; }
die() { printf '[apollo] error: %s\n' "$*" >&2; exit 1; }

has_auth_stack() {
  local file="$1"
  [[ -f "$file" && ! -L "$file" ]] || return 1
  grep -Eq '^[[:space:]]*auth[[:space:]]+' "$file"
}

is_apollo_pam() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  grep -q 'APOLLO_KSCREENLOCKER_PAM' "$file"
}

is_wrapper_text() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  head -n 15 "$file" | grep -q 'APOLLO_KSCREENLOCKER_GREET_WRAPPER'
}

# Arch's kscreenlocker file is only "auth include system-local-login".
# That include is a login policy (pam_shells, pam_nologin), not a locker check.
is_stock_kde_pam() {
  local file="$1"
  local line lines
  [[ -f "$file" && ! -L "$file" ]] || return 1
  lines="$(grep -E '^[[:space:]]*auth[[:space:]]+' "$file" || true)"
  [[ -n "$lines" ]] || return 1
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*auth[[:space:]]+include[[:space:]]+system-local-login[[:space:]]*$ ]] || return 1
  done <<<"$lines"
}

install_kde_pam() {
  local etc_dir="${APOLLO_PAM_ETC:-/etc/pam.d}"
  local template="${APOLLO_PAM_TEMPLATE:-/usr/local/share/apollo/pam/kde}"
  local etc_file="$etc_dir/kde"

  [[ -f "$template" ]] || die "PAM template missing ($template)"

  if [[ -f "$etc_file" && ! -L "$etc_file" ]]; then
    if ! is_apollo_pam "$etc_file" && ! is_stock_kde_pam "$etc_file" && has_auth_stack "$etc_file"; then
      log "PAM service kde: keeping custom $etc_file"
      log "warning: unlock expects Apollo's pam_unix stack in $etc_file. Move that file aside and re-run ./install.sh if the correct password still fails."
      return 0
    fi
  fi

  mkdir -p "$etc_dir"
  install -m 0644 "$template" "$etc_file"
  log "installed locker PAM $etc_file (pam_unix; does not include system-local-login)"
}

install_lock_shell() {
  local src="${APOLLO_LOCK_SHELL_SRC:-/usr/local/share/apollo/lockscreen}"
  local dest="${APOLLO_LOCK_SHELL_DEST:-/usr/local/share/plasma/shells/org.kde.apollo}"

  [[ -f "$src/metadata.json" ]] || die "lock screen metadata missing ($src/metadata.json)"
  [[ -f "$src/contents/lockscreen/LockScreen.qml" ]] || die "lock screen QML missing ($src/contents/lockscreen/LockScreen.qml)"
  mkdir -p "$dest/contents/lockscreen"
  install -m 0644 "$src/metadata.json" "$dest/metadata.json"
  install -m 0644 "$src/contents/lockscreen/LockScreen.qml" "$dest/contents/lockscreen/LockScreen.qml"
  log "installed lock screen $dest"
}

pick_greet_bin() {
  if [[ -n "${APOLLO_GREET_BIN:-}" ]]; then
    printf '%s\n' "$APOLLO_GREET_BIN"
    return 0
  fi
  local candidate
  for candidate in /usr/lib/kscreenlocker_greet /usr/libexec/kscreenlocker_greet; do
    if [[ -e "$candidate" || -L "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

wrap_greeter() {
  local wrapper="${APOLLO_GREET_WRAPPER:-/usr/local/share/apollo/scripts/kscreenlocker-greet-wrapper.sh}"
  local bin real src wrapper_real target

  [[ -x "$wrapper" ]] || die "greeter wrapper missing or not executable ($wrapper)"
  wrapper_real="$(readlink -f "$wrapper")"

  if ! bin="$(pick_greet_bin)"; then
    die "kscreenlocker_greet not found; cannot wrap the lock greeter"
  fi
  if [[ ! -e "$bin" && ! -L "$bin" ]]; then
    die "kscreenlocker_greet not found ($bin)"
  fi
  real="${APOLLO_GREET_REAL:-${bin}.apollo-real}"

  if [[ -L "$bin" ]]; then
    target="$(readlink -f "$bin" 2>/dev/null || true)"
    if [[ "$target" == "$wrapper_real" && -x "$real" && ! -L "$real" ]] && ! is_wrapper_text "$real"; then
      log "kscreenlocker greeter already wrapped ($bin)"
      return 0
    fi
  elif is_wrapper_text "$bin" && [[ -x "$real" && ! -L "$real" ]] && ! is_wrapper_text "$real"; then
    log "kscreenlocker greeter already wrapped ($bin)"
    return 0
  fi

  if [[ -L "$bin" ]]; then
    src="$(readlink -f "$bin" 2>/dev/null || true)"
    [[ -n "$src" && -f "$src" ]] || die "kscreenlocker_greet symlink has no target ($bin)"
  else
    src="$bin"
  fi
  if is_wrapper_text "$src"; then
    die "real kscreenlocker_greet binary missing ($bin is the wrapper). Reinstall the kscreenlocker package, then re-run ./install.sh"
  fi

  # Copy first, then replace the path KWin execs. If the link step fails,
  # the distro binary is still at $bin.
  cp -a "$src" "$real"
  chmod 0755 "$real"
  ln -sfn "$wrapper" "$bin"
  log "wrapped $bin → $wrapper (binary saved as $real)"
}

install_kde_pam
install_lock_shell
wrap_greeter

# Universe KWin

Minimal **Arch Linux** desktop stack:

- **KWin** (Wayland compositor + title bars / decorations)
- **Quickshell** (bar / shell UI — no `plasmashell`)
- hooks for a future Go **`universed`** settings daemon

Designed to run right after a fresh Arch install from a **TTY**.

## Requirements

- Arch Linux with network
- A normal user in the `wheel` group (`sudo` works)
- UEFI/BIOS already set up; you can finish the Arch install guide through creating a user, then run this before or after enabling a display manager

## Install (TTY)

```bash
sudo pacman -Syu --needed git base-devel
git clone https://github.com/kinplus127/Apollo.git && cd Apollo && ./install.sh
sudo reboot
```

At SDDM, pick **Universe (KWin + Quickshell)**.

> Or copy this folder onto the machine (`scp` / USB) and run `./install.sh`.

## What it installs

Official repos: `kwin`, `breeze`, portals, `polkit-kde-agent`, Qt6 Wayland bits, PipeWire, `sddm`, NetworkManager, BlueZ, etc.

AUR: `yay` (if missing), then `quickshell`.

It does **not** install `plasma`, `plasma-meta`, or `plasma-desktop`.

## Layout after install

| Path | Role |
|---|---|
| `/usr/local/bin/universe-kwin-session` | SDDM session entrypoint |
| `/usr/local/share/universe-kwin/scripts/start-universe.sh` | starts Quickshell + `kwin_wayland` |
| `/usr/local/share/wayland-sessions/universe-kwin.desktop` | session desktop file |
| `~/.config/quickshell/universe/shell.qml` | stub bar (safe to edit) |
| `~/.config/kwinrc` | created only if missing |

## Next steps

1. Replace the Quickshell stub with your real shell.
2. Add tiling via a KWin Script (e.g. Krohnkite) after first GUI login.
3. Build `universed` and put it on `PATH`; the session script will autostart it.

## Re-run

`./install.sh` is idempotent for user configs: existing `shell.qml` / `kwinrc` are kept.

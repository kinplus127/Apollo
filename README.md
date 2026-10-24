# Apollo

Minimal **Arch Linux** desktop stack:

- **KWin** (Wayland compositor + title bars / decorations)
- **Quickshell** (bar / shell UI — no `plasmashell`)
- **greetd + tuigreet** (TTY greeter — not SDDM)
- **NVIDIA** proprietary driver with DRM modeset for Wayland
- hooks for a future Go **`universed`** settings daemon (your unified settings center)

## Install (TTY)

```bash
sudo pacman -Syu --needed git base-devel
git clone https://github.com/kinplus127/Apollo.git ~/Apollo
cd ~/Apollo
./install.sh
sudo reboot
```

At **tuigreet**, pick **Universe (KWin + Quickshell)**.

## What `universed` is

`universed` is the planned name for the Go daemon behind your **unified settings center**: system + appearance + behaviour (Wi‑Fi, Bluetooth, monitors, Quickshell look & feel, keybinds, exec/autostart). The session script starts it automatically once the binary is on `PATH`. It is **not** installed by this script yet.

## Layout after install

| Path | Role |
|---|---|
| `/usr/local/bin/universe-kwin-session` | greetd/tuigreet session entrypoint |
| `/usr/local/share/universe-kwin/scripts/start-universe.sh` | starts Quickshell + `kwin_wayland` |
| `/usr/local/share/wayland-sessions/universe-kwin.desktop` | session desktop file |
| `/etc/greetd/config.toml` | tuigreet as default greeter |
| `/etc/modprobe.d/nvidia.conf` | `nvidia_drm modeset=1` |
| `~/.config/quickshell/universe/shell.qml` | stub bar |
| `~/.config/kwinrc` | created only if missing |

## Re-run

`./install.sh` is idempotent for user configs: existing `shell.qml` / `kwinrc` are kept.

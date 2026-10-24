# Apollo

Minimal **Arch Linux** desktop environment:

- **KWin** (Wayland compositor + title bars / decorations)
- **Quickshell** (bar / shell UI — no `plasmashell`)
- **greetd** autologin (no greeter UI — not tuigreet / SDDM)
- **fish** as the account login shell
- **kitty**, **yazi**, **Neovim + LazyVim**
- **Brave** (official, AUR `brave-origin-bin`)
- **Fonts:** IBM Plex (GitHub desktop OTF, including CJK), Noroshi Code, Apple Color Emoji, Symbols Nerd Font
- **NVIDIA** `nvidia-open` + `nvidia-utils` + `libva-nvidia-driver`
- hooks for a future Go **`apollod`** settings daemon (unified settings center)

## Install (TTY)

```bash
sudo pacman -Syu --needed git base-devel
git clone https://github.com/kinplus127/Apollo.git ~/Apollo
cd ~/Apollo
./install.sh
sudo reboot
```

After reboot, greetd starts **Apollo** as the installing user with no login screen.

## What `apollod` is

`apollod` is the planned Go daemon behind your **unified settings center**: system + appearance + behaviour (Wi‑Fi, Bluetooth, monitors, Quickshell look & feel, keybinds, exec/autostart). The session script starts it automatically once the binary is on `PATH`. It is **not** installed by this script yet.

## Layout after install

| Path | Role |
|---|---|
| `/usr/local/bin/apollo-session` | greetd session entrypoint |
| `/usr/local/share/apollo/scripts/start-apollo.sh` | starts Quickshell + `kwin_wayland` |
| `/usr/local/share/wayland-sessions/apollo.desktop` | session desktop file |
| `/etc/greetd/config.toml` | autologin into Apollo (no greeter) |
| `~/.config/quickshell/apollo/shell.qml` | stub bar |
| `~/Pictures/wallpapers/` | default wallpapers (exact copy from repo) |
| `~/.config/kwinrc` | created only if missing |
| `~/.local/share/fonts/ibm-plex/` | IBM Plex desktop OTF |
| `~/.local/share/fonts/noroshi/` | Noroshi Code hinted TTF |

## Re-run

`./install.sh` is idempotent for user configs: existing `shell.qml` / `kwinrc` are kept.

## Default keybinds (installed)

| Shortcut | Action | Notes |
|---|---|---|
| Super+Q | Close focused window | Remaps KWin **Window Close** (Alt+F4 still works) |
| Super+T | Launch **kitty** | Takes former Meta+T slot from Edit Tiles |
| Super+Shift+T | KWin **Edit Tiles** | Tiling layout editor (moved off Super+T) |

Conflict check: Plasma/KWin default **Meta+T = Edit Tiles** — we move that to **Meta+Shift+T** so Super+T can open kitty. **Meta+Q** is Activities in full Plasma; Apollo does not ship plasmashell, so it is free for close.

## Where to put keybinds


| Layer | Config |
|---|---|
| KWin (WM / window / global hotkeys) | `~/.config/kwinrc` |
| Quickshell (bar / shell UI) | `~/.config/quickshell/apollo/` |
| kitty | `~/.config/kitty/kitty.conf` |
| Neovim (LazyVim) | `~/.config/nvim/` (LazyVim `keymaps.lua` etc.) |
| Session env / autostart only | `scripts/start-apollo.sh` — **not** for keybinds |

Later, **apollod** can centralize DE/shell binds; app tools still use their own configs.

## Fonts

`install.sh` installs desktop faces only (no web woff/woff2):

| Family | Source | Role |
|---|---|---|
| IBM Plex Sans, Serif, Mono, Condensed, Math, and Sans TC / SC / JP / KR / Arabic / Hebrew / Devanagari / Thai / Thai Looped | GitHub [IBM/plex](https://github.com/IBM/plex) `fonts/complete/otf` (hinted CJK) | UI sans is **IBM Plex Sans**. CJK falls back to **IBM Plex Sans TC**, then SC, JP, KR, and the other Plex script families |
| Noroshi Code | GitHub [Honoka55/noroshi](https://github.com/Honoka55/noroshi) hinted TTF | Terminal / monospace. **IBM Plex Mono** is the Latin fallback. Bold and italic stay in Noroshi Code |
| Apple Color Emoji | AUR `ttf-apple-emoji` | Emoji fallback. The package's optional `75-apple-color-emoji.conf` is not enabled |
| Symbols Nerd Font / Symbols Nerd Font Mono | extra `ttf-nerd-fonts-symbols` and `ttf-nerd-fonts-symbols-mono` (`ttf-nerd-fonts-symbols-common` is a dependency) | Icon fallback, appended after text faces |

Defaults are written to:

- fontconfig `~/.config/fontconfig/conf.d/60-apollo-fonts.conf`
- GTK `~/.config/gtk-3.0/settings.ini` and `~/.config/gtk-4.0/settings.ini` (`IBM Plex Sans 11`)
- GSettings `org.gnome.desktop.interface` `font-name`, `document-font-name`, and `monospace-font-name` (`Noroshi Code 11`) when `gsettings` and `gsettings-desktop-schemas` work
- Qt / KDE `~/.config/kdeglobals`
- kitty `font_family Noroshi Code`

Re-run updates those font keys and leaves other kitty, GTK, and `kdeglobals` settings in place. `shell.qml` and `kwinrc` are still left untouched when they already exist.

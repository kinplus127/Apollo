# Apollo

Minimal **Arch Linux** desktop environment:

- **KWin** (Wayland compositor) with stock **Breeze** window decorations, colours, and **breeze-icons**
- **Quickshell** (bar / shell UI — no `plasmashell`)
- **PCManFM-Qt** file manager and **pavucontrol-qt** volume mixer
- **greetd** + **tuigreet** password login (no autologin, no SDDM)
- **fish** as the account login shell
- **fcitx5** — 速成 (Quick3) and 日本語 Mozc (ローマ字)
- **kitty**, **yazi**, **Neovim + LazyVim**
- **Brave** (official, AUR `brave-origin-bin`)
- **Fonts:** IBM Plex (GitHub desktop OTF, including CJK), Noroshi Code, Apple Color Emoji, Symbols Nerd Font
- **awww** wallpaper daemon (official `awww`, the successor of swww)
- **Spectacle** screenshots (installed; Apollo does not bind a shortcut)
- **cliphist**, **wl-clipboard**, and **wl-clip-persist** (clipboard history; the regular clipboard survives after the source app exits)
- **NVIDIA** `nvidia-open` + `nvidia-utils` + `libva-nvidia-driver`
- hooks for a future Go **`apollod`** settings daemon (unified settings center)

Global shortcuts that Apollo used to ship (Super+T, Super+C, Super+L, and the rest) are **intentionally disabled**. See [Shortcuts](#shortcuts-intentionally-disabled).

## Install (TTY)

```bash
sudo pacman -Syu --needed git base-devel
git clone https://github.com/kinplus127/Apollo.git ~/Apollo
cd ~/Apollo
./install.sh
sudo reboot
```

After reboot, **tuigreet** asks for a username and password. A successful login runs `/usr/local/bin/apollo-session` (KWin + Quickshell). Logout returns to the greeter. greetd does not autologin: `/etc/greetd/config.toml` has no `[initial_session]` block.

The template is `config/greetd/config.toml`. `./install.sh` copies it to `/etc/greetd/config.toml` (root) and creates `/var/cache/tuigreet` owned by the `greeter` user so `--remember` can pre-fill the last username. `--remember` does not store or skip the password. Re-running `./install.sh` rewrites that greetd file.

`./install.sh` asks for the sudo password **once**. Package installs, greetd, and files under `/usr/local` reuse that authentication, including across long builds. Fonts and everything under your home directory do not use sudo. `sudo reboot` afterwards is a separate command.

## What `apollod` is

`apollod` is the planned Go daemon behind your **unified settings center**: system + appearance + behaviour (Wi‑Fi, Bluetooth, monitors, Quickshell look & feel, keybinds, exec/autostart). The session script starts it automatically once the binary is on `PATH`. It is **not** installed by this script yet.

## Layout after install

| Path | Role |
|---|---|
| `/usr/local/bin/apollo-session` | greetd session entrypoint |
| `/usr/local/share/apollo/scripts/start-apollo.sh` | starts Quickshell, awww, clipboard helpers, and `kwin_wayland` |
| `/usr/local/share/wayland-sessions/apollo.desktop` | session desktop file (tuigreet lists it; the default command is still `apollo-session`) |
| `/etc/greetd/config.toml` | tuigreet password login, then Apollo. No autologin |
| `config/greetd/config.toml` | template installed to the path above |
| `~/.config/quickshell/apollo/shell.qml` | stub bar and notification toasts |
| `~/Pictures/wallpapers/` | default wallpapers; awww picks one at login |
| `~/.config/kwinrc` | created only if missing; decoration is Breeze |
| `~/.config/kdeglobals` | fonts, Breeze colour scheme, Breeze icons, Breeze widget style |
| `~/.config/kglobalshortcutsrc` | created only if missing, with Apollo's shortcuts unbound |
| `~/.config/fish/conf.d/apollo.fish` | Puts `/usr/local/bin` and `~/.local/bin` on fish's `PATH` |
| `~/.local/share/fonts/ibm-plex/` | IBM Plex desktop OTF |
| `~/.local/share/fonts/noroshi/` | Noroshi Code hinted TTF |

## Re-run

`./install.sh` does not replace an existing `shell.qml` or `kwinrc`. If `kwinrc` still points at an Aurorae / NT Legacy decoration, that run switches the decoration library and theme to Breeze. If `kdeglobals` still names an NT Legacy colour scheme or icon theme, the copied NT palette is removed and Breeze is written back. NT Legacy files under `~/.local/share` and `~/.local/bin/apollo-theme-nt` are removed. `/etc/greetd/config.toml` is rewritten from the template.

## Shortcuts (intentionally disabled)

Apollo does not bind Meta/Super. kitty, Spectacle, the lock script, and the logout script are still installed; they have no Apollo shortcut.

`config/kglobalshortcutsrc.snippet` is the disabled stub (`none`, except Alt+F4 to close a window). `install.sh` copies it only when `~/.config/kglobalshortcutsrc` is missing. If a previous Apollo install wrote Meta/Super on those actions, that run sets those lines to `none` and leaves every other shortcut in the file alone. `scripts/start-apollo.sh` does not start `kglobalacceld`.

The actions that used to be bound, and are now unbound:

| Was | Action |
|---|---|
| Super+Q | Close focused window |
| Super+T | Launch kitty |
| Super+Shift+T | KWin Edit Tiles |
| Super+L | Lock session |
| Super+Shift+L | Log out |
| Super+C | Spectacle region |
| Super+Shift+C | Spectacle full screen |

To re-enable later:

1. In `config/kglobalshortcutsrc.snippet`, replace the live `none` values with the commented bindings, and copy that file over `~/.config/kglobalshortcutsrc` (or merge the lines yourself).
2. Copy `session/kitty.desktop` to `~/.local/share/kglobalaccel/kitty.desktop`.
3. On Plasma older than 6.8, start `kglobalacceld` from `scripts/start-apollo.sh`. Plasma 6.8 and newer handle those shortcuts inside KWin, so the daemon is unnecessary there.
4. Log out and back in.

Lock and logout still work from a terminal: `/usr/local/share/apollo/scripts/apollo-lock.sh` and `apollo-logout.sh`. Screenshots: `spectacle`, `spectacle --background --region`, or `spectacle --background --fullscreen`.

## Input method

fcitx5 starts with the session (`fcitx5 -d`) and these variables: `XMODIFIERS=@im=fcitx`, `GTK_IM_MODULE=fcitx`, `QT_IM_MODULE=fcitx`, `SDL_IM_MODULE=fcitx`.

The seeded profile (`~/.config/fcitx5/profile`, only if you do not already have one) enables **速成** (`Quick3`, the zh_HK table from `fcitx5-table-extra`) and **日本語 Mozc** (ローマ字, `fcitx5-mozc`), plus the US keyboard. An existing profile is left as it is.

## Lock and unlock

Apollo does not bind Super+L. Lock from a terminal:

```bash
/usr/local/share/apollo/scripts/apollo-lock.sh
```

That runs `loginctl lock-session`, then the KDE screensaver D-Bus `Lock` methods. KWin starts `kscreenlocker_greet`. plasmashell is not involved. The password is checked by PAM service `kde`. tuigreet's login PAM is a different path and is left as it is.

Arch's `kscreenlocker` package ships the locker service as `/usr/lib/pam.d/kde` (`auth include system-local-login`). `install.sh` writes `/etc/pam.d/kde` from `config/pam/kde` only when neither that path nor `/usr/lib/pam.d/kde` already has an auth stack. On the next `install.sh` or `kscreenlocker` upgrade, an Apollo-written fallback is removed once the package file has an auth stack.

The session still exports `QT_IM_MODULE=fcitx`, and the seeded profile defaults to 速成. KWin copies the session environment into the greeter, and on Wayland the greeter does not clear `QT_IM_MODULE` (KDE bug 306932). 速成 then holds the keystrokes and the candidate window cannot appear on the lock screen, so the password looks dead. `install.sh` points `/usr/lib/kscreenlocker_greet` at `kscreenlocker-greet-wrapper.sh`, which sets `QT_IM_MODULE=compose` for that process only. Kitty, the browser, and other clients keep fcitx5. A pacman hook reapplies the wrapper after a `kscreenlocker` upgrade.

From a logged-in Apollo session:

1. Run `apollo-lock.sh` (or `loginctl lock-session`). The lock screen appears.
2. Type the account password and press Enter. The session unlocks.
3. 速成 and Mozc still work in an application after unlock.

If the screen stays locked, switch to another TTY (Ctrl+Alt+F3), log in as the same user, and unlock this session:

```bash
loginctl list-sessions
loginctl unlock-session SESSION_ID
```

Ctrl+Alt+F1 returns to the tuigreet VT. `loginctl terminate-session SESSION_ID` ends the locked session instead. tuigreet asks for the password again, and unsaved work in the old session is gone.

鎖定與解鎖：Apollo 沒有綁定 Super+L。在終端機執行 `/usr/local/share/apollo/scripts/apollo-lock.sh`（或 `loginctl lock-session`），由 KWin 啟動 `kscreenlocker_greet`，密碼經 PAM 服務 `kde` 核對。tuigreet 的登入密碼維持不變。工作階段的 fcitx5（速成、Mozc）維持不變；解鎖程式會改用 `QT_IM_MODULE=compose`，密碼按鍵才會進入欄位。`kscreenlocker` 升級後，pacman hook 會重新套上這個包裝。解鎖失敗時，到另一個 TTY 登入，執行 `loginctl list-sessions`，再執行 `loginctl unlock-session SESSION_ID`。`loginctl terminate-session SESSION_ID` 會結束該工作階段，tuigreet 會再詢問密碼，尚未儲存的資料會消失。

## Session bus

`apollo-session` runs `start-apollo.sh` inside `dbus-run-session` when `DBUS_SESSION_BUS_ADDRESS` is unset, so KWin, Quickshell, and fcitx5 share one session bus. If a bus is already present, it is not wrapped again.

## Where to put keybinds

| Layer | Config |
|---|---|
| KWin (WM / window / global hotkeys) | `~/.config/kwinrc` and `~/.config/kglobalshortcutsrc` |
| Quickshell (bar / shell UI) | `~/.config/quickshell/apollo/` |
| kitty | `~/.config/kitty/kitty.conf` |
| Neovim (LazyVim) | `~/.config/nvim/` (LazyVim `keymaps.lua` etc.) |
| Session env / autostart only | `scripts/start-apollo.sh` — **not** for keybinds |

Apollo's own global shortcuts stay disabled until the steps above. Later, **apollod** can centralize DE/shell binds; app tools still use their own configs.

## Appearance

New installs use stock Breeze:

| Layer | Value |
|---|---|
| Window decoration | `library=org.kde.breeze`, `theme=Breeze` in `~/.config/kwinrc` |
| Colour scheme | `Breeze` |
| Icons | `breeze` |
| Qt widget style | `breeze` |

`start-apollo.sh` sets `QT_QPA_PLATFORMTHEME=kde`. `plasma-integration` reads `kdeglobals`. That package is not `plasmashell`.

## File manager and volume

**PCManFM-Qt** (`pcmanfm-qt`) is the file manager. Its desktop module (`pcmanfm-qt --desktop`) is `OnlyShowIn=LXQt` and does not start in an Apollo session. Apollo does not rewrite `mimeapps.list`.

**pavucontrol-qt** is the Qt PulseAudio mixer. There is no Quickshell button for it. It needs a Pulse socket; Apollo installs `pipewire-pulse` (do not also install `pulseaudio`). The command is `pavucontrol-qt`.

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

Re-run updates those font keys and leaves other kitty, GTK, and `kdeglobals` settings in place, except the NT Legacy reset described above. `shell.qml` is left untouched when it already exists. An existing `kwinrc` is not replaced wholesale.

## Wallpaper

Login starts **awww** (`awww-daemon` + `awww img`). The package is official extra `awww`, which provides and replaces `swww`; `swww` is not installed. If that package is absent from the mirror, the installer falls back to AUR `awww-git`.

The session picks a random `jpg`, `jpeg`, `png`, `webp`, `gif`, or `bmp` from `~/Pictures/wallpapers/` (`$XDG_PICTURES_DIR` when set). A missing or empty folder, or an awww failure, is a warning only — KWin still starts.

## Screenshots and clipboard

**Spectacle** (official `spectacle`) takes screenshots. Apollo does not bind Super+C or Super+Shift+C. Run `spectacle --background --region` for a region (saved, no viewer), `spectacle --background --fullscreen` for the whole desktop, or `spectacle` for the window.

Clipboard history is **cliphist**, written by `wl-paste --watch cliphist store` (cliphist has no `watch` subcommand). **wl-clip-persist --clipboard regular** keeps that clipboard after the application you copied from exits. **wl-clipboard** is the copy/paste tool underneath. A history picker can wait until Apollo has a launcher. Until then, recall an entry with `cliphist list | cliphist decode | wl-copy`. A missing helper is a warning only — KWin still starts.

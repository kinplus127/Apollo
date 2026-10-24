# Apollo

Minimal **Arch Linux** desktop environment:

- **KWin** (Wayland compositor + title bars / decorations) and **breeze-icons**
- **NT Legacy 98** day/night title bars, colours, and icons (Qt Windows widget style; no `plasmashell`)
- **Quickshell** (bar / shell UI — no `plasmashell`)
- **PCManFM-Qt** file manager and **pavucontrol-qt** volume mixer
- **greetd** autologin (no greeter UI — not tuigreet / SDDM)
- **fish** as the account login shell
- **fcitx5** — 速成 (Quick3) and 日本語 Mozc (ローマ字)
- **kitty**, **yazi**, **Neovim + LazyVim**
- **Brave** (official, AUR `brave-origin-bin`)
- **Fonts:** IBM Plex (GitHub desktop OTF, including CJK), Noroshi Code, Apple Color Emoji, Symbols Nerd Font
- **awww** wallpaper daemon (official `awww`, the successor of swww)
- **Spectacle** screenshots
- **cliphist**, **wl-clipboard**, and **wl-clip-persist** (clipboard history; the regular clipboard survives after the source app exits)
- **NVIDIA** `nvidia-open` + `nvidia-utils` + `libva-nvidia-driver`
- hooks for a future Go **`apollod`** settings daemon (unified settings center)

## Install (TTY)

```bash
sudo pacman -Syu --needed git base-devel
git clone https://github.com/kinplus127/Apollo.git ~/Apollo
cd ~/Apollo
# This checkout must contain scripts/apollo-theme-nt.sh.
# Use this branch, or main after that change is merged. An older tree
# finishes without the theme command.
./install.sh
sudo reboot
```

After reboot, greetd starts **Apollo** as the installing user with no login screen.

`apollo-theme-nt` is installed only by that `./install.sh`. If fish in kitty says `Unknown command: apollo-theme-nt` (exit 127), the command was never copied to `/usr/local/bin` — the install stopped early, or the checkout is older than the theme script. Open a new terminal after a finished install and run:

```bash
command -v apollo-theme-nt
apollo-theme-nt status
```

`command -v` should print `/usr/local/bin/apollo-theme-nt`. fish also reads `~/.config/fish/conf.d/apollo.fish`, which adds `/usr/local/bin` and `~/.local/bin` to `PATH`. If `/usr/local/bin` could not be written, the installer leaves `~/.local/bin/apollo-theme-nt` and then stops.

`apollo-theme-nt` 只會由這份 `./install.sh` 裝上。fish 若顯示 `Unknown command: apollo-theme-nt`（結束碼 127），代表 `/usr/local/bin` 沒有這個指令：安裝提早中止，或這個目錄還是舊的程式樹。請改用包含 `scripts/apollo-theme-nt.sh` 的分支（合併後則用 `main`），在該目錄再執行 `./install.sh`。完成後開一個新終端機：

```bash
command -v apollo-theme-nt
apollo-theme-nt status
```

`./install.sh` asks for the sudo password **once**. Package installs, greetd, and files under `/usr/local` reuse that authentication, including across long builds. Fonts, the NT Legacy theme, and everything under your home directory do not use sudo. `sudo reboot` afterwards is a separate command.

`./install.sh` 只會詢問一次 sudo 密碼。套件、greetd 與 `/usr/local` 會沿用該授權，包括耗時較長的編譯。字型、NT Legacy 主題，以及家目錄內的檔案不會使用 sudo。最後的 `sudo reboot` 是另一次指令。

## What `apollod` is

`apollod` is the planned Go daemon behind your **unified settings center**: system + appearance + behaviour (Wi‑Fi, Bluetooth, monitors, Quickshell look & feel, keybinds, exec/autostart). The session script starts it automatically once the binary is on `PATH`. It is **not** installed by this script yet.

## Layout after install

| Path | Role |
|---|---|
| `/usr/local/bin/apollo-session` | greetd session entrypoint |
| `/usr/local/share/apollo/scripts/start-apollo.sh` | starts Quickshell, awww, clipboard helpers, and `kwin_wayland` |
| `/usr/local/share/wayland-sessions/apollo.desktop` | session desktop file |
| `/etc/greetd/config.toml` | autologin into Apollo (no greeter) |
| `~/.config/quickshell/apollo/shell.qml` | stub bar and notification toasts |
| `~/Pictures/wallpapers/` | default wallpapers; awww picks one at login |
| `~/.config/kwinrc` | created only if missing; decoration keys follow NT Legacy |
| `/usr/local/bin/apollo-theme-nt` | NT Legacy 98 day/night switch (`toggle` is the future Quickshell hook). Missing when install stops early |
| `~/.local/bin/apollo-theme-nt` | Fallback link only if `/usr/local/bin` could not be written; install then stops |
| `~/.config/fish/conf.d/apollo.fish` | Puts `/usr/local/bin` and `~/.local/bin` on fish's `PATH` |
| `~/.local/share/aurorae/themes/` | NT Legacy 98 and 98 Night window decorations |
| `~/.local/share/color-schemes/NTLegacyWin98*.colors` | matching colour schemes |
| `~/.local/share/icons/NTLegacyIcons/` | NT icons; `NTLegacyIconsNacht` is derived at install |
| `~/.local/share/fonts/ibm-plex/` | IBM Plex desktop OTF |
| `~/.local/share/fonts/noroshi/` | Noroshi Code hinted TTF |

## Re-run

`./install.sh` does not replace an existing `shell.qml` or `kwinrc`. Each run applies the NT Legacy variant already chosen (day the first time). That refreshes the Aurorae keys and copies the colour scheme into `kdeglobals`. It does not switch a chosen night variant back to day.

## Default keybinds (installed)

| Shortcut | Action | Notes |
|---|---|---|
| Super+Q | Close focused window | Remaps KWin **Window Close** (Alt+F4 still works) |
| Super+T | Launch **kitty** | Takes former Meta+T slot from Edit Tiles |
| Super+Shift+T | KWin **Edit Tiles** | Tiling layout editor (moved off Super+T) |
| Super+L | Lock session | `loginctl lock-session`, then the KDE screensaver D-Bus interface |
| Super+Shift+L | Log out | `loginctl terminate-session` for this session |
| Super+C | Capture a rectangular region | `spectacle --background --region` (selector, then save; no viewer) |
| Super+Shift+C | Capture the full desktop | `spectacle --background --fullscreen` |

Conflict check: Plasma/KWin default **Meta+T = Edit Tiles** — we move that to **Meta+Shift+T** so Super+T can open kitty. The binding is `[services][kitty.desktop]` in `kglobalshortcutsrc`. Plasma 6.8 runs that shortcut service inside KWin, so the session does not start a separate daemon. If `/usr/lib/kglobalacceld` exists (older Plasma), `start-apollo.sh` starts it. A copy of `kitty.desktop` is also placed in `~/.local/share/kglobalaccel/` so the shortcut still resolves when the KService cache does not list kitty yet. **Meta+Q** is Activities in full Plasma; Apollo does not ship plasmashell, so it is free for close. **Meta+L** is Plasma's lock shortcut; here it runs Apollo's locker script instead of plasmashell. **Meta+C** and **Meta+Shift+C** were unused. **Ctrl+C** is left as copy / interrupt.

## Input method

fcitx5 starts with the session (`fcitx5 -d`) and these variables: `XMODIFIERS=@im=fcitx`, `GTK_IM_MODULE=fcitx`, `QT_IM_MODULE=fcitx`, `SDL_IM_MODULE=fcitx`.

The seeded profile (`~/.config/fcitx5/profile`, only if you do not already have one) enables **速成** (`Quick3`, the zh_HK table from `fcitx5-table-extra`) and **日本語 Mozc** (ローマ字, `fcitx5-mozc`), plus the US keyboard. An existing profile is left as it is.

## Session bus

`apollo-session` runs `start-apollo.sh` inside `dbus-run-session` when `DBUS_SESSION_BUS_ADDRESS` is unset, so KWin, Quickshell, fcitx5, and the lock shortcut share one session bus. If a bus is already present, it is not wrapped again.

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

Re-run updates those font keys and leaves other kitty, GTK, and `kdeglobals` settings in place. `shell.qml` is left untouched when it already exists. An existing `kwinrc` is not replaced wholesale. Each run still writes the NT decoration keys and colour groups for the variant already chosen.

## NT Legacy 98（Windows 98 配色）

Apollo 只安裝標題列與 Qt 程式需要的層次，並以日間 **win98**、夜間 **win98-nacht** 成對切換。不安裝 Plasma 面板、Look and Feel／Global Theme，亦不依賴 `plasmashell`。上游的 GRUB、Plymouth、游標、Konsole 色彩及牆紙故意略去。

來源是 [huppiflupp/plasma-theme-lab](https://github.com/huppiflupp/plasma-theme-lab) 的 `nt-legacy/`（GPL-2.0-or-later）。`install.sh` 以 sparse checkout 取得資產，做法與字型相同：記錄上游 commit，修訂變動時才重新下載。夜間圖示上游沒有入庫，安裝時由日間圖示派生，只把繼承鏈改為 Breeze Dark。

已安裝的層次：

| 層次 | 日間 | 夜間 |
|---|---|---|
| Aurorae 標題列 | `NTLegacyWin98` | `NTLegacyWin98Nacht` |
| 色彩方案 | `NTLegacyWin98` | `NTLegacyWin98Nacht` |
| 圖示 | `NTLegacyIcons`（繼承 Breeze） | `NTLegacyIconsNacht`（繼承 Breeze Dark） |
| Qt 控制項 | `widgetStyle=Windows`（Qt 內建 Windows 9x 樣式，不用 Kvantum） | 同左 |

`start-apollo.sh` 設定 `QT_QPA_PLATFORMTHEME=kde`，由 `plasma-integration` 讀取 `kdeglobals`。此套件不是 `plasmashell`。色彩不是只寫 `ColorScheme` 名稱：`plasma-integration` 在 `kdeglobals` 已有 `Colors:*` 時會忽略該名稱，所以腳本會把方案內容抄進 `kdeglobals`（與 `plasma-apply-colorscheme` 相同，但不安裝 `plasmashell`）。Qt 沒有內建 `Windows` widget style 時，套用會直接失敗。

切換（四層同時寫入；Quickshell 日後可呼叫 `toggle`，目前沒有按鈕）：

```bash
apollo-theme-nt day
apollo-theme-nt night
apollo-theme-nt toggle
apollo-theme-nt status
```

`status` 印出 `variant=`、`coherent=` 及各層名稱。`toggle` 在日間與夜間之間對調；若設定混雜或尚未套用，則改為日間。

Aurorae 標題列在 KWin 啟動時載入。KWin 6.6 及之後會在登入時把 decoration library 從 `org.kde.kwin.aurorae` 改寫成 `org.kde.kwin.aurorae.v2`；主題名稱維持 `__aurorae__svg__NTLegacyWin98`（或夜間的 `NTLegacyWin98Nacht`）。腳本會通知 KWin 重新讀取設定。若標題列或色彩仍是舊的，請再執行一次後登出再登入：

```bash
apollo-theme-nt day
```

已選夜間時用 `apollo-theme-nt night`。已開啟的 Qt 程式可能要重新開啟，才會使用新的色彩、圖示與 Windows 控制項樣式。

Meta+T 由 KWin 內建的全域快捷鍵服務啟動 kitty（Plasma 6.8 不再另外執行 `kglobalacceld`）。改完設定後同樣需要登出一次，工作階段才會讀到新的 `kglobalshortcutsrc`。

### 檔案總管與音量

**PCManFM-Qt**（`pcmanfm-qt`）用作檔案總管：Dolphin 的剩餘空間列往往不理會 Windows widget style。套用主題時會把 PCManFM-Qt 的 `IconThemeName` 與 `FallbackIconThemeName` 設成目前的 NT 圖示。其桌面模組（`pcmanfm-qt --desktop`）的 autostart 標明 `OnlyShowIn=LXQt`，Apollo 工作階段不會啟動它。

`inode/directory` 只在 `~/.config/mimeapps.list` 尚未指定時設為 `pcmanfm-qt.desktop`。還原方法：刪去 `[Default Applications]` 下該行。已有其他檔案總管時，安裝程式不會覆寫。

**pavucontrol-qt** 是 Qt 版 PulseAudio 音量控制，只加入安裝清單，沒有 Quickshell 按鈕。它需要 Pulse 插座；Apollo 安裝 `pipewire-pulse`（不要另外安裝 `pulseaudio`）。啟動指令是 `pavucontrol-qt`。

English: the same pair is what `apollo-theme-nt` writes. Panels, Global Theme, GRUB, and Plymouth from upstream are omitted on purpose. If the frame or colours stay on the previous look, run `apollo-theme-nt day` (or `night` if that is the variant you kept) and log out once. Meta+T launches kitty after that login. A future Quickshell button should call `apollo-theme-nt toggle` and does not exist yet.

## Wallpaper

Login starts **awww** (`awww-daemon` + `awww img`). The package is official extra `awww`, which provides and replaces `swww`; `swww` is not installed. If that package is absent from the mirror, the installer falls back to AUR `awww-git`.

The session picks a random `jpg`, `jpeg`, `png`, `webp`, `gif`, or `bmp` from `~/Pictures/wallpapers/` (`$XDG_PICTURES_DIR` when set). A missing or empty folder, or an awww failure, is a warning only — KWin still starts.

## Screenshots and clipboard

**Spectacle** (official `spectacle`) takes screenshots. Super+C runs `spectacle --background --region`: the region selector appears, and the shot is saved without the Spectacle viewer. Super+Shift+C runs `spectacle --background --fullscreen` and exits. `spectacle` with no arguments opens the full window.

Clipboard history is **cliphist**, written by `wl-paste --watch cliphist store` (cliphist has no `watch` subcommand). **wl-clip-persist --clipboard regular** keeps that clipboard after the application you copied from exits. **wl-clipboard** is the copy/paste tool underneath. A history picker can wait until Apollo has a launcher. Until then, recall an entry with `cliphist list | cliphist decode | wl-copy`. A missing helper is a warning only — KWin still starts.

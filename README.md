# quickshell_dark

My Hyprland bar, launcher, notifications and popups, written for [Quickshell](https://quickshell.org). It is a personal config first. It runs on my Arch machine every day, and a few features still call scripts that live outside this repo (listed below). Without them those features do nothing, and the rest of the shell still works.

## What it needs

- Quickshell 0.3.2 or newer, built against the Qt you have installed. I run it on Qt 6.12.
- Hyprland 0.56 or newer with a Lua config (`hyprland.lua`). The shell talks to Hyprland in Lua, so the old `hyprland.conf` format will not work.
- PipeWire with `pactl` and `pw-play`, `notify-send`, `xdg-open`, ImageMagick (`magick`) and GNU coreutils.
- Fonts: Symbols Nerd Font for the icons, plus Inter and IosevkaTerm Nerd Font Mono by default. You can change the last two in settings.

Hyprland has to tell the shell about clicks, or popups will not close when you click outside them. Add these two lines to your Hyprland config:

```lua
hl.bind("mouse:272", hl.dsp.event("click"), { non_consuming = true })
hl.bind("mouse:273", hl.dsp.event("click"), { non_consuming = true })
```

Scrolling over the workspaces and dragging a window onto one call three Lua functions from my own Hyprland config: `workspace_cycle(delta)`, `move_window_to(id, address)` and `insert_window_at(id, address)`. They are not published yet, so those two actions do nothing until you define functions with those names.

## Install

```sh
git clone https://github.com/tkutsu/quickshell_dark ~/.config/quickshell
qs
```

On first run the shell copies `settings.default.json` to `settings.json`. Change settings with the gear in the bar or by editing `settings.json`, which is picked up on save. Every setting is explained in `settings.default.json`.

## Optional features

Each of these turns on when its tools are installed. Without them the rest of the shell keeps working.

| Feature | Needs |
| --- | --- |
| Wi-Fi | NetworkManager (`nmcli`) |
| Bluetooth | BlueZ (`busctl`) |
| Drives | UDisks2 (`udisksctl`), UPower |
| Music | MPD and `mpc`, with MPD listening on the socket set in `mpdSocket` |
| Launcher file search | `fd` |
| Calculator | `qalc` |
| Clipboard history | `cliphist`, `wl-clipboard`, and `wl-paste --watch cliphist store` running in your session |
| Package updates | Arch only: `checkupdates` (pacman-contrib) and `yay` |
| GPU stats | NVIDIA only: `nvidia-smi` |
| Weather | Python 3, no account needed |
| Google Tasks, Calendar, Gmail | Your own Google Cloud OAuth client. Run `scripts/gtasks-auth` once, or press reconnect in any of their popups. |
| Phone alarms | A Pushover app. Put `{"token": "...", "user": "..."}` in `~/.local/share/quickshell/pushover.json`. |

## Scripts outside this repo

Some actions run scripts from `scriptsDir` (`~/_scripts` by default): `power.sh` for the power menu, `display.sh` for brightness and night mode, `thumb.sh` for file previews, `taskbar-satty.sh` for screenshots, and `taskbar-update.sh` for updates. They are not published yet. Gmail and Calendar use `pwa-gmail.sh` and `pwa-gcalendar.sh` when you have them and open in your browser when you do not.

## License

The code is under the MIT license (see `LICENSE`). Any copy or derivative work has to keep the copyright notice. The icons and the alarm sound come from other projects and keep their own licenses. `icons/README.md` says where each icon comes from.

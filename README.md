# quickshell_dark

My Hyprland bar, launcher, notifications and popups, written for [Quickshell](https://quickshell.org). It is a personal config first. It runs on my Arch machine every day, and a few features still call scripts that live outside this repo (listed below). Without them those features do nothing, and the rest of the shell still works.

## Features

### The bar

- The bar is three pills of clear glass: workspaces on the left, music, clock and timers in the middle, and status and controls on the right. The glass bends the wallpaper behind it at the rim like a lens, and the pills that come and go beside the clock merge into it like drops.
- Each workspace shows one icon per app. A click opens an app's group into one icon per window, an urgent window marks its app, and you can drag a window onto another workspace. Scrolling over the workspaces steps through them.
- Popups grow out of the item that opened them. While one is open, resting the pointer on another item switches to that item's popup. Tooltips appear when the pointer rests and stay away while a popup is open.
- Quiet modules fold into a drawer behind a chevron in the right pill and come back when they have something to show. You can pin any of them outside the drawer from the settings window, or with a middle click.
- The wallpaper pans with a spring as you change workspace, and Hyprland's active border takes its colour from the wallpaper.
- The gear opens a settings window with a search box. It writes `settings.json` for you.
- The power menu covers sleep, restart, shut down, log out, and kill a window by clicking it.

### The launcher

One box for everything. Typed on its own, a query finds apps, ranked by how well they match and how often and recently you picked them. A sum gets an answer, and a query that finds nothing is offered as a web search. A leading character picks a mode:

| Prefix | Mode |
| --- | --- |
| `/` | Files, with a preview of the selected file or folder |
| `_` | Open windows, to jump to one |
| `"` | Clipboard history |
| `%` | Web search. `%lofi` searches Google, and a one-letter engine first picks another: `%y lofi` for YouTube, then ChatGPT, Claude, Translate, Maps and more |
| `@` | Gmail: unread mail, readable in place, or a search of the whole mailbox |
| `,` | A new Google task, or a timer or alarm when the text starts with a duration or a time of day |
| `#` | The MPD library by artist, album and track, plus stored playlists |
| `=` | Calculator |
| `>` | Run a shell command |

### What it does on its own

- Notifications: the shell is the notification server. A new one appears beside the clock, and the bell holds the rest, with actions, images and do not disturb.
- Timers and alarms: countdowns you can pause and adjust, and alarms that can repeat on chosen weekdays. They survive a restart and can also ring your phone through Pushover.
- Google: the Tasks count and list, the Calendar agenda inside the clock's calendar, and the Gmail unread count with mark-as-read.
- Weather from Open-Meteo between the date and the time, with an hourly graph and a city search. No account needed.
- Music: an MPD client with the cover, a seek bar, volume, and a queue you can reorder.
- Audio: pick the output, set the volume, and set each app's volume.
- Wi-Fi and Bluetooth: scan, connect and disconnect from their popups.
- Removable drives show up while plugged in, with how full each one is and a safe eject. So do wired devices that report a battery, such as a mouse on a USB receiver.
- System: CPU or GPU temperature on the bar, and a popup with memory, top processes and the graphics card.
- Package updates (Arch): the pending count, the list, and a button that runs the upgrade.
- Wallpapers: a picker with every image in your folder.
- Night mode: warmer colour and a dimmed monitor, on a schedule or by hand.
- Caffeine to keep the screen awake, a screenshot button, the keyboard layout, and a system tray with its menus.

Most of it can be driven from keybinds too: `qs ipc call launcher toggle`, `qs ipc call timer toggle`, and similar targets for `power`, `notifications`, `tasks`, `email`, `agenda`, `updates`, `caffeine` and `settings`.

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

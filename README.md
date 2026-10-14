# dewdrop

My Hyprland bar, launcher, notifications and popups, written for [Quickshell](https://quickshell.org). It is a personal config first. It runs on my Arch machine every day, and a few features still call scripts that live outside this repo (listed below). Without them those features do nothing, and the rest of the shell still works.

## Features

### Bar

- Clear glass pills that bend the wallpaper at the rim; pills beside the clock merge into it like drops
- One icon per app on each workspace, drag a window to another workspace, scroll to switch
- Popups grow from their item and switch on hover once one is open; the arrows walk an open popup, Return presses, Escape closes
- Quiet modules fold into a drawer; pin any of them from settings or with a middle click
- Wallpaper pans as you change workspace; the window border takes its colour
- Settings window with search, including macOS's Reduce motion and Reduce transparency
- Power menu: sleep, restart, shut down, log out, kill a window

### Launcher

Apps by default, ranked by match and frecency. Sums get answered, and anything else falls back to a web search.

Starts with a magnifier, Search field and mode hints. Press Down or Enter with an empty query to browse frecency. Typing hides the hints, reveals matches, and selects the first match. Email addresses offer a Gmail search. The query stays pinned while the list opens and its shadow deepens. Rows fade and move up in sequence, 32 ms apart, including when opening directly into a mode.

The launcher opens with a sideways spring based on the Spotlight reference: its width settles while text, height and corners keep their size. Closing retracts the sides. Reduce motion skips the spring.

Long queries scroll horizontally with a soft fade at the hidden edges. The search icon stays fixed, the caret stays clear, and the full query remains editable and selectable.

| Prefix | Mode |
| --- | --- |
| `/` | Files, with preview. Ctrl+Enter shows the file in its folder, Ctrl+C copies its path |
| `_` | Open windows; `_firefox` searches them, then falls back if none match |
| `"` | Clipboard history |
| `%` | Web search (`%y lofi` for YouTube, also ChatGPT, Claude, Translate, Maps) |
| `@` | Gmail: unread, read in place, search |
| `,` | Google task, timer, alarm or calendar event (see below) |
| `#` | MPD library and playlists |
| `=` | Calculator |

The more of a time a `,` line gives, the bigger the thing it makes. Events last an hour and go on the primary calendar.

| Typed | Makes |
| --- | --- |
| `, call bank` | task in the default task list |
| `, work call bank` | task in the Work task list |
| `, fri call bank` | task due Friday |
| `, 25m tea` | timer |
| `, 15:00 call bank` | alarm at 15:00 and an event 15:00–16:00 on the day it rings |
| `, today 15:00 call bank` | event today 15:00–16:00, no alarm |
| `, fri 15:00 call bank` | event Friday 15:00–16:00 |
| `, 2026-11-03 9:30 dentist` | event on that date |

Right-clicking a day in the calendar opens the launcher with that day typed in.

Paths also select file mode automatically. Names starting with `_` try windows first.
HTML/XHTML files open in the default application; other text files open in the editor.
Settings > Launcher > Desktop actions shows or hides all app shortcuts together. They start hidden.

### Built in

- Notification server, with a notification centre
- Timers and repeating alarms, with optional Pushover phone alerts
- Google Tasks, Calendar agenda, Gmail unread
- Weather (Open-Meteo, no account)
- MPD player with cover, seek and an editable queue
- Audio output and per-app volume
- Recording indicator: while an app uses a microphone or shares the screen, a pill with a red dot comes out of the right pill; its popup mutes an app's mic or stops the share
- Wi-Fi and Bluetooth
- Removable drives with safe eject, device batteries
- CPU/GPU temperature, memory, top processes
- Arch package updates
- Wallpaper picker
- Night mode with schedule
- Caffeine, screenshots, keyboard layout, tray

Keybinds can drive it over IPC: `qs ipc call launcher toggle`, plus targets for `timer`, `power`, `notifications`, `tasks`, `email`, `agenda`, `updates`, `caffeine`, `settings`.

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
git clone https://github.com/tkutsu/dewdrop ~/.config/quickshell
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

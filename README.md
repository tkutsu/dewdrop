# dewdrop

My Hyprland bar, launcher, notifications and popups, written for [Quickshell](https://quickshell.org). It is a personal config first. It runs on my Arch machine every day, and a few features still call scripts that live outside this repo (listed below). Without them those features do nothing, and the rest of the shell still works.

## Features

### Bar

- Clear glass pills that bend the wallpaper at the rim; pills beside the clock merge into it like drops
- One icon per app on each workspace, drag a window to another workspace, scroll to switch
- Popups grow from their item and switch on hover once one is open; the arrows walk an open popup, Return presses, Escape closes
- Quiet modules fold into a drawer; pin any of them from settings or with a middle click
- Drag modules to reorder them or move them between the central and right pills, keeping at least one in the centre. Settings > Modules controls their visibility.
- Paused MPD and MPRIS players collapse to a music note or app icon beside the clock; click to expand them again
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
| `.` | Web search (`.y lofi` for YouTube, also ChatGPT, Claude, Translate, Maps) |
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

Cancelling a named alarm also removes the Google Calendar event created with it.
Turning the alarm off or dismissing it after it rings keeps the event. This link
is saved for new alarms; alarms created before this feature keep their events.
If Calendar cannot remove the event, QS shows a notification; remove it in Calendar.

Paths also select file mode automatically. Names starting with `_` try windows first.
HTML/XHTML files open in the default application; other text files open in the editor.
File search includes hidden and Git-ignored files, while respecting `.ignore` files and the optional ignore file in Settings > Launcher > File Search.
Settings > Launcher Apps > Desktop Actions shows or hides all app shortcuts together. They start hidden.

### Built in

- Notification server, with a notification centre
- Timers and repeating alarms, with optional local Android phone alerts
- Google Tasks, Calendar agenda
- Feeds: new videos from your YouTube subscriptions and any other channels you add, without Shorts, livestreams or premieres, plus RSS or Atom feeds (Hacker News by default). Each source folds under a header with its count. An item stays listed until you open it, swipe it away (undoable) or open it in Firefox or a Chromium-based browser, whose local history is checked for the listed links only
- Gmail's unread (the whole inbox, or the tabs picked in settings), cleared from the popup: archive, mark read and star on every row or by swiping it, each undoable for a few seconds; login codes to copy, attachments to save, unsubscribe; a notification for each new mail
- Weather (Open-Meteo, no account), with an hourly forecast and a seven-day outlook showing the predominant daylight condition and a second icon when the worst condition differs
- MPD player with cover, seek and an editable queue
- Now Playing for browsers and other MPRIS apps, with an app icon, play/pause and scroll to seek; hide it in Settings > Music
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

## Icons

Dewdrop does not require Themis. The SVGs used for its own controls are bundled in `icons/`; other interface glyphs use Symbols Nerd Font. Application icons in the left bar and application and file icons in the launcher come from desktop entries and your active system icon theme. They are not bundled. Missing icons fall back to a generic glyph.

For a matching monochrome look, install [Themis Icons](https://github.com/tkutsu/themis-icons) and select `themis` as your Qt icon theme. It completes the theme visually, especially in the left bar and launcher, but other icon themes work too.

## Optional features

Each of these turns on when its tools are installed. Without them the rest of the shell keeps working.

| Feature | Needs |
| --- | --- |
| Wi-Fi | NetworkManager (`nmcli`) |
| Bluetooth | BlueZ (`busctl`) |
| Drives | UDisks2 (`udisksctl`), UPower |
| Music | MPD and `mpc`, with MPD listening on the socket set in `mpdSocket` |
| Music equalizer | Python 3, FFmpeg, and a user `mpd.service`. The config at `mpdConfig` must have one FFmpeg EQ filter attached to an output and a `state_file` to preserve the queue. Apply saves a `.quickshell-eq.bak` backup and briefly restarts MPD. |
| Launcher file search | `fd` |
| File previews | `file`; `pdftoppm` (poppler) for PDFs, `ffmpeg` for videos, LibreOffice (`soffice`) for office documents. ImageMagick handles additional image formats. Missing renderers leave a generic icon. |
| Calculator | `qalc` |
| Clipboard history | `cliphist`, `wl-clipboard`, and `wl-paste --watch cliphist store` running in your session |
| Package updates | Arch only: `checkupdates` (pacman-contrib) and `yay` |
| GPU stats | NVIDIA only: `nvidia-smi` |
| Weather | Python 3, no account needed |
| Google Tasks, Calendar, Gmail | Your own Google Cloud OAuth client and one sign-in. See [Google setup](#google-setup). |
| YouTube in Feeds | The same OAuth client and a second sign-in for the account that holds your subscriptions. See [Google setup](#google-setup). The RSS feeds need nothing. |
| Phone alarms | Android Automate and Python 3. Direct home Wi-Fi delivery; follow the [Automate setup tutorial](automate-setup.md). See [phone-alarms.md](phone-alarms.md) for configuration and protocol details. |

## Google setup

Tasks, Calendar, Gmail and the YouTube half of Feeds talk to Google with your own OAuth client, so there is no shared app to trust. Set it up once in the [Google Cloud console](https://console.cloud.google.com/) before running `scripts/gtasks-auth`.

1. Create a project, or pick one you already have.
2. Under APIs & Services, enable the APIs for what you use: Google Tasks API, Google Calendar API and Gmail API for the main sign-in, and YouTube Data API v3 for Feeds. Signing in does not enable them. A popup that says an API is not enabled means this step was missed; the error names the project.
3. Under Google Auth Platform, fill in the Branding page: app name, user support email and developer contact email. The app domain links can stay empty.
4. Under Audience, choose External and publish the app to In production. While it is in Testing, Google expires its refresh tokens after 7 days and the bar asks you to reconnect every week. Do not submit it for verification; you are its only user.
5. Under Clients, create an OAuth client of type Desktop app. Keep the client ID and client secret; the script asks for them the first time.

Then sign in:

```sh
scripts/gtasks-auth            # Tasks, Calendar and Gmail
scripts/gtasks-auth --youtube  # Feeds, only if you want your YouTube subscriptions
```

Each run opens your browser on Google's account chooser. For the first, pick the account with your mail. For the second, pick the account or YouTube channel that holds your subscriptions. A brand account works here, but not for the first sign-in, because it has no Gmail. Google then warns that it has not verified the app: choose Advanced, then Go to your app. The script waits up to 15 minutes for the browser and saves the tokens to `~/.local/share/quickshell/gtasks.json` and `youtube.json`, readable only by you. The second run reuses the client from the first.

`scripts/gtasks-auth --check` and `scripts/gtasks-auth --youtube --check` test the saved sign-ins and list what they can reach. After the first sign-in, the Reconnect and Connect YouTube buttons in the popups run the script for you.

## Scripts outside this repo

Power, display, update and cleanup actions still use external helpers from `scriptsDir` (`~/_scripts` by default). File previews use the bundled `scripts/thumb.sh`.

The update and cleanup runner opens a new dropdown pane, starting the dropdown when needed. It waits about five seconds for the control socket, then falls back to a regular Kitty window if the dropdown is unavailable.

Settings > Default Apps > Screenshots accepts a shell command. The bar adds no arguments and expects no output; the tool handles selection, editing, saving and the clipboard. An empty command hides the screenshot button. Settings > Launcher > File Search accepts an optional fd ignore file, which can also be shared with a terminal file picker.

Gmail, Google Calendar and Google Tasks open their installed Chromium PWAs when available, or their websites otherwise. Settings > Mail and Settings > Tasks & Calendar let you choose another installed app or always use the website. Mail also has its attachment folder; Default Apps > External Helpers has the scripts folder. Settings > Appearance has fonts and the wallpaper folder. Parallax zoom stays in the wallpaper popup. The music directory is read directly from MPD when it connects.

### TODO: Remaining external helpers

- [ ] Bundle power actions and the blackout shader while preserving the external session-save command.
- [ ] Bundle display control with settings for the monitor bus and colour temperatures, keeping keyboard shortcuts on the same implementation.
- [ ] Bundle the updater and terminal runner, including dropdown detection; keep Arch and Kitty dependencies explicit.
- [ ] Add a configurable external cleanup command for machine-specific maintenance.
- [ ] Point the remaining Google setup hint at the bundled `scripts/gtasks-auth`.

## License

The code is under the MIT license (see `LICENSE`). Any copy or derivative work has to keep the copyright notice. The icons and the alarm sound come from other projects and keep their own licenses. `icons/README.md` says where each icon comes from.

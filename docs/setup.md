# Setup And Reference

Start with the [installation steps in the README](../README.md#install). Run the commands below from the repository directory.

## Requirements And Hyprland Integration

- Quickshell 0.3.2 or newer, built against the Qt you have installed. I run it on Qt 6.12.
- Hyprland 0.56 or newer with a Lua config (`hyprland.lua`). The shell talks to Hyprland in Lua, so the old `hyprland.conf` format will not work.
- PipeWire with `pactl` and `pw-play`, `notify-send`, `xdg-open`, ImageMagick (`magick`) and GNU coreutils.
- systemd for the power actions, and a terminal. With `terminal` empty in settings, the bar uses the first of kitty, foot, alacritty and ghostty it finds. Popups hide the buttons that need one you do not have, and say so.
- Fonts: Symbols Nerd Font for the icons, plus Inter and IosevkaTerm Nerd Font Mono by default. You can change the last two in settings.

The bar needs a few things from Hyprland: click events so popups close, layer rules and blur for the glass, popup fades, and the functions behind scrolling and dragging workspaces. They are all in `hypr/dewdrop.lua`. Load it near the top of `hyprland.lua`, so your own settings win where they overlap:

```lua
dofile(os.getenv("HOME") .. "/.config/quickshell/hypr/dewdrop.lua")
```

That file also renumbers numbered workspaces to close gaps as they empty, and names workspace 10 "0". It returns the workspace module, for keybinds you want on the same ring of workspaces as the bar.

Keep the top of `gaps_out` at 8, which is `Theme.barMargin`. The bar reserves its strip counting on that gap, so another value changes the space under the bar.

## Icons

Dewdrop does not require Themis. The SVGs used for its own controls are bundled in `icons/`; other interface glyphs use Symbols Nerd Font. Application icons in the left bar, the launcher and notifications come from an icon theme, and missing icons fall back to a generic glyph.

The bar asks for [Themis Icons](https://github.com/tkutsu/themis-icons) by name, whatever your system's icon theme is, because its monochrome icons are what the bar is drawn around. Install it into `~/.local/share/assets/icons/themis` or `/usr/share/assets/icons/themis`. Until you do, the bar uses plain hicolor icons and Settings > Appearance links to it. To use another theme in the bar, change `//@ pragma IconTheme themis` at the top of `shell.qml` to that theme's name.

## Optional features

Each of these turns on when its tools are installed. Without them the rest of the shell keeps working. Where a program is missing, the popup that would use it says which package it needs, and Settings says the same under the module or power action. The launcher's calculator and file search say it in their results, where Return installs it. The Install link beside it runs `sudo pacman -S --needed` with that package in your terminal, and the feature appears once the terminal closes, with no restart. Set `installCommand` to install some other way; package names are Arch's.

| Feature | Needs |
| --- | --- |
| Wi-Fi | NetworkManager running when the bar starts; the Network module hides without it. `nm-connection-editor` opens the full settings from the popup and a right click (`networkCommand`) |
| Bluetooth | BlueZ (`busctl`), and `blueman-manager` for the button and right click that open the full settings (`bluetoothCommand`) |
| Brightness | On a monitor: `ddcutil`, the `i2c-dev` kernel module and access to `/dev/i2c-*` (usually the `i2c` group). On a laptop panel: `brightnessctl`. The Display module hides without them. |
| Night mode tint | `hyprsunset` running in your session. Without it, night mode only dims the screen. |
| Lock Screen | Something that answers `loginctl lock-session`, such as `hypridle` with `lock_cmd = hyprlock` |
| Black screen animation on sleep | `gdbus` (glib2). Without it sleep runs with no animation. |
| Drives | UDisks2 (`udisksctl`), UPower |
| Music | MPD and `mpc`, with MPD listening on the socket set in `mpdSocket` |
| Music equalizer | Python 3, FFmpeg, and a user `mpd.service`. The config at `mpdConfig` must have one FFmpeg EQ filter attached to an output and a `state_file` to preserve the queue. Apply saves a `.quickshell-eq.bak` backup and briefly restarts MPD. |
| Launcher file search | `fd`, and `fasd` for recent files |
| File previews | `file`; `pdftoppm` (poppler) for PDFs, `ffmpeg` for videos, LibreOffice (`soffice`) for office documents. ImageMagick handles additional image formats. Missing renderers leave a generic icon. |
| Calculator | `qalc` |
| Clipboard history | `cliphist`, `wl-clipboard`, and `wl-paste --watch cliphist store` running in your session |
| Package updates | Arch only: `checkupdates` (pacman-contrib), and `yay` to include the AUR. The module hides without `checkupdates`. |
| GPU stats | NVIDIA only: `nvidia-smi` |
| Full system monitor | `btop` in your terminal, opened from the system popup and by a right click (`monitorCommand`) |
| Weather | Python 3, no account needed. The module hides without it. |
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

## Commands you can set

Settings > Default Apps holds these, the first three under Updates and the rest under Other Commands. `settings.default.json` documents them too.

| Setting | What it does | When empty |
| --- | --- | --- |
| Upgrade Command (`updateCommand`) | Runs from the Upgrade button in the updates popup | `yay` if it is installed, or else `sudo pacman -Syu` |
| Clean Up Command (`cleanupCommand`) | Runs from the Clean Up button beside it | The button is hidden |
| Open In Terminal (`commandsInTerminal`) | On by default: Upgrade and Clean Up run in your terminal. Turn it off when those two commands open their own, like a dropdown | |
| Session Save Command (`sessionSaveCommand`) | Runs before logging out, to save your windows | Nothing is saved |
| Install Command (`installCommand`) | Runs from an Install link, in the terminal, with Arch package names after it | `sudo pacman -S --needed` where pacman is installed, or else no Install links |
| Monitor Bus (`displayBus`) | The DDC/CI bus from `ddcutil detect`, which is quicker than searching for the monitor | The first monitor |

Settings > Default Apps > Right Click sets what a right click on Network, Bluetooth and System opens: `networkCommand` (`nm-connection-editor`), `bluetoothCommand` (`blueman-manager`) and `monitorCommand` (`btop`, run in the terminal). An empty one hides the button in that popup, and a right click opens the popup instead.

Power and brightness run the bundled `scripts/power.sh` and `scripts/display.sh`. A keybind can call `scripts/display.sh` too, with `up`, `down` or `toggle`.

Settings > Default Apps > Screenshots accepts a shell command. The bar adds no arguments and expects no output; the tool handles selection, editing, saving and the clipboard. An empty command hides the screenshot button. Settings > Launcher > File Search accepts an optional fd ignore file, which can also be shared with a terminal file picker.

Gmail, Google Calendar and Google Tasks open their installed Chromium PWAs when available, or their websites otherwise. Settings > Mail and Settings > Tasks & Calendar let you choose another installed app or always use the website. Mail also has its attachment folder. Settings > Appearance has fonts and the wallpaper folder. Parallax zoom stays in the wallpaper popup. The music directory is read directly from MPD when it connects.

## Testing on a fresh install

`tests/fresh-install-test` boots the official Arch cloud image in a throwaway KVM virtual machine. It installs Hyprland, Quickshell and the requirements above, and nothing else, then logs in to Hyprland with a `hyprland.lua` that loads `hypr/dewdrop.lua` and starts the bar from your checkout. A minute later it brings back a screenshot and the bar's log, and lists the log's errors. It needs `qemu-system-x86_64`, `qemu-img` and access to `/dev/kvm`. Results go to `~/.cache/dewdrop-fresh-test/runs/`.

## Launcher Reference


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
| `?` | These modes; Enter goes to the selected one |

Settings > Launcher > Mode Symbols changes these characters. The rest of this section uses the defaults.

In `@` mode, names and email addresses match fuzzily above message results. For example, `@sampl` can suggest `rsample@example.com`; selecting it fills a `from:` search. Gmail search operators still work as typed.

The first `@` starts a background scan of sender and recipient headers across the mailbox, including Spam and Trash. Suggestions fill in as the scan progresses. Its SQLite cache under `$XDG_CACHE_HOME/quickshell/gmail-addresses.sqlite` (normally `~/.cache/quickshell/`) keeps addresses and scan progress across restarts. Later scans use Gmail's change history; an expired history cursor restarts the listing without rereading headers already indexed. Discovered addresses stay available after their messages are deleted. This uses the existing Gmail permission and does not require Google Contacts access.

The more of a time a `,` line gives, the bigger the thing it makes, and the query line shows the forms while it holds only the `,`. Events last an hour and go on the primary calendar.

| Typed | Makes |
| --- | --- |
| `, call bank` | task in the default task list |
| `, work call bank` | task in the Work task list |
| `, fri call bank` | task due Friday |
| `, 25m tea` | timer |
| `, 15:00 call bank` | alarm at 15:00 |
| `, today 15:00 call bank` | event today 15:00-16:00 |
| `, fri 15:00 call bank` | event Friday 15:00-16:00 |
| `, 2026-11-03 9:30 dentist` | event on that date |

Right-clicking a day in the calendar opens the launcher with that day typed in.

Paths also select file mode automatically. Names starting with `_` try windows first.
HTML/XHTML files open in the default application; other text files open in the editor.
File search includes hidden and Git-ignored files, while respecting `.ignore` files and the optional ignore file in Settings > Launcher > File Search.
Settings > Launcher Apps > Desktop Actions shows or hides all app shortcuts together. They start hidden.

# <img src="docs/icon.svg" alt="" width="40" align="top"> dewdrop

A glass bar and keyboard launcher for Hyprland, built with [Quickshell](https://quickshell.org). It's the bar I use every day.

![Dewdrop's glass bar with workspaces, music, the clock and controls](docs/media/bar.webp)

## The Bar

Switch workspaces and a glass mark slides over to the new one, bouncing a little at either end, while the wallpaper drifts behind it. Scroll over the strip to switch, or drag a window onto another workspace.

![The workspace pill, with the glass mark moving between apps as the wallpaper slides behind it](docs/media/workspaces.gif)

Controls you don't reach for often fold into a drawer. Drag modules to reorder them or move them between the centre and the right, and pin the ones you want in view.

![The right drawer opening to show the rest of the controls](docs/media/drawer.gif)

The clock and the weather hold the middle. Music joins them on the left, the bell and timers on the right, each only while it has something going. A notification slides out beside them, then folds into the bell.

![The centre pill: a timer coming out, music pausing and resuming, then a notification folding into the bell](docs/media/pills.gif)

## The Launcher

One shortcut for the small stuff: open apps, preview files, jump to a window, search your clipboard, pick an emoji, read mail, browse your music, do quick maths, or type in a task, timer, alarm or calendar event. Type `?` for every mode and your Hyprland keybinds.

![A keyboard launcher tour through every mode](docs/media/launcher-tour.gif)

## Popovers

Calendar, mail, tasks and feeds open in popovers that grow out of the bar, and all of them work from the keyboard.

![Calendar, task, mail, feed, notification, music and timer popovers](docs/media/popovers-productivity.gif)

Weather, per-app volume, Wi-Fi, Bluetooth, battery and sleep timers, and the system controls are there too. Settings are searchable, with Reduce Motion and Reduce Transparency for when the bouncing and the glass get to be too much.

![Weather, audio, network, display and system-control popovers](docs/media/popovers-controls.gif)

## Lock Screen And Passwords

Locking fades your windows into the wallpaper and raises a pane of glass with the time, the weather, what came in while you were away and the password field. PIN Mode checks the password once it reaches the length you set, without Return.

Dewdrop is also your polkit agent. When `pkexec` or an app needs an administrator's password, it asks in a small glass panel, and shakes it if the password is wrong.

## Install

Dewdrop is my personal config, and I run it on Arch Linux. It needs Quickshell 0.3.2 or newer and Hyprland 0.56 or newer with a Lua config (`hyprland.lua`).

### 1. Install The Packages

In a Hyprland session, install Quickshell from Arch's official repository, with the tools and fonts the bar uses:

```sh
sudo pacman -Syu --needed quickshell git python pipewire-pulse wireplumber libnotify imagemagick ttf-nerd-fonts-symbols inter-font ttf-iosevkaterm-nerd
```

You also need a terminal. Dewdrop uses kitty, foot, alacritty or ghostty, whichever you have.

### 2. Get Dewdrop

Move any other config in `~/.config/quickshell` aside first.

```sh
git clone https://github.com/tkutsu/dewdrop ~/.config/quickshell
```

### 3. Connect It To Hyprland

Load the integration near the top of `~/.config/hypr/hyprland.lua`, before your own overrides. It supplies the blur, popup dismissal and workspace helpers, and starts the bar with Hyprland:

```lua
dofile(os.getenv("HOME") .. "/.config/quickshell/hypr/dewdrop.lua")
```

Then bind the launcher and the lock screen. Pick other keys if these are taken, and replace any bind that ran `hyprlock`:

```lua
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("qs ipc call launcher toggle"))
hl.bind("SUPER + ESCAPE", hl.dsp.exec_cmd("qs ipc call lock lock"))
```

Before you log out and back in:

- Remove any exec line of your own that runs `qs` or `quickshell`.
- Remove your old polkit agent, since only one can run per session. The [setup guide](docs/setup.md#polkit-agent) lists the common ones.
- Keep the top outer gap at 8 pixels so windows line up below the bar.
- If you use hypridle, point it at Dewdrop's lock and remove its display-off and suspend listeners, as in [Lock screen and hypridle](docs/setup.md#lock-screen-and-hypridle). Dewdrop turns the display off and sleeps on its own timers.
- If you have your own Escape or close-window binds, see [Escape and close keybinds](docs/setup.md#escape-and-close-keybinds).

If the bar ever stops on its own, Hyprland says so, and Super+Ctrl+Alt+V starts it again.

### 4. Make It Yours

Open the gear in the bar to choose modules, your wallpaper folder and default apps. Your changes go to `settings.json`, which reloads on save; [the default settings](settings.default.json) explain each option.

For the monochrome app icons in the GIFs, install [Themis Icons](https://github.com/tkutsu/themis-icons), or set another theme in the icon-theme pragma in `shell.qml`.

File search, the calculator, clipboard history and a few other features need their own tools, and Mail, Tasks, Calendar and YouTube need your own Google OAuth client. The [setup guide](docs/setup.md) covers [those dependencies](docs/setup.md#optional-features), [Google sign-in](docs/setup.md#google-setup) and [the launcher](docs/setup.md#launcher-reference). [Android phone alarms](docs/automate-setup.md) have their own tutorial.

## Troubleshooting

If something doesn't work, see [Troubleshooting](docs/troubleshooting.md).

## License

[MIT](LICENSE). Bundled icons and the alarm sound keep their own licenses; see [icon credits](assets/icons/README.md).

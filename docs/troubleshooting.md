# Troubleshooting

| Symptom | What To Check |
| --- | --- |
| The bar is gone, and the launcher with it | Press Super+Ctrl+Alt+V to start it again. If it stops again, open a terminal with your Hyprland terminal shortcut, which works without the bar, and follow the next row. |
| The bar does not start | Run `qs -n` from a terminal inside Hyprland and read the first error. Check `qs --version` and `hyprctl version`. For a running instance, `qs log -t 80` shows recent messages. |
| It broke after a Qt update | [Quickshell must match the installed Qt libraries](https://github.com/quickshell-mirror/quickshell/blob/master/BUILD.md). Fully update Arch with `sudo pacman -Syu`; if you built Quickshell yourself, rebuild it against the updated Qt. |
| Glass looks flat, or outside clicks do not close popovers | Check that `hypr/dewdrop.lua` is loaded, reload Hyprland and check for config errors. Turn off Reduce Transparency in Dewdrop's settings if you want the glass effect. |
| A password prompt comes from another app, or none comes at all | Only one polkit agent can run per session. Remove the others, as in [Polkit agent](setup.md#polkit-agent), then restart Hyprland. If Dewdrop could not register, `qs log -t 80` shows a polkit warning. |
| Icons are boxes or look different | Install Symbols Nerd Font for glyphs and [Themis Icons](https://github.com/tkutsu/themis-icons) for the app icons in the README. Relaunch the bar after installing fonts or an icon theme. |
| A module is missing or clipboard history is empty | Open the drawer: every module is listed there, even one with nothing to show yet. Check its place in Settings and its [optional dependencies](setup.md#optional-features). Wi-Fi needs NetworkManager running when the bar starts. Clipboard history needs `wl-paste --watch cliphist store` running in your session. |
| Install links or terminal buttons are missing | They need a terminal. Install kitty, foot, alacritty or ghostty, or set `terminal` in settings. |
| Google features fail or ask to reconnect every week | Enable the relevant APIs in your Cloud project and follow [Google setup](setup.md#google-setup). Google [expires these refresh tokens after 7 days in Testing](https://developers.google.com/identity/protocols/oauth2/#expiration). Run `scripts/gtasks-auth --check` from the repo to check the saved sign-in. |

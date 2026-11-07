#!/usr/bin/env bash
set -euo pipefail

# Replace the final compositor output, including windows and wallpaper.
set_screen_shader() {
  local shader=${1//\\/\\\\} response
  shader=\"${shader//\"/\\\"}\"
  response=$(hyprctl eval "hl.config({ decoration = { screen_shader = $shader } })") || return
  if [[ $response != ok ]]; then
    printf '%s\n' "$response" >&2
    return 1
  fi
}

# Keep black independently of Quickshell; runtime settings reset next login.
case ${1-} in
--poweroff|--reboot|--logout)
  if previous_shader=$(hyprctl getoption decoration:screen_shader | sed -n 's/^str: //p') && [[ -n $previous_shader ]]; then
    [[ $previous_shader != '[[EMPTY]]' ]] || previous_shader=''
    trap 'power_status=$?; if ((power_status != 0)); then set_screen_shader "$previous_shader" || true; fi' EXIT
    power_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    set_screen_shader "$power_dir/power-blackout.frag" || true
  fi
  ;;
esac

case ${1-} in
--poweroff)
  systemctl poweroff
  ;;
--reboot)
  systemctl reboot
  ;;
--suspend)
  systemctl suspend
  ;;
--hibernate)
  systemctl hibernate
  ;;
--logout)
  # The second argument is settings.json's sessionSaveCommand. A save that fails
  # must not stop the logout.
  [[ -z ${2-} ]] || sh -c "$2" || true
  hyprctl dispatch 'hl.dsp.exit(1)'
  ;;
--kill)
  # "kill process" entry in the power menu: Hyprland's click-to-kill mode, where
  # the next click picks the window to kill. Detached with a short delay so the
  # menu is gone before the crosshair goes live.
  (sleep 0.3 && hyprctl kill) >/dev/null 2>&1 &
  ;;
--lock)
  loginctl lock-session ${XDG_SESSION_ID-}
  ;;
*)
  echo "usage: ${0##*/} --poweroff|--reboot|--suspend|--hibernate|--lock|--kill|--logout [session save command]" >&2
  exit 1
  ;;
esac

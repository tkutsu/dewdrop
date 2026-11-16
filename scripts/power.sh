#!/usr/bin/env bash
set -euo pipefail

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

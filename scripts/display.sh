#!/usr/bin/env bash
#
# display.sh — screen brightness and night mode.
#
# A laptop panel has a kernel backlight, driven through brightnessctl. Anything
# else is a monitor over DDC/CI (VCP 0x10), driven through ddcutil. hyprsunset
# does the tint, when it is running.
#
# Brightness and night mode both end up writing the same panel and the same
# cache, so they share one lock. Split across two scripts, a keybind toggle
# landing mid-scroll left the monitor at one value and the cache at another —
# and the cache is what the bar shows and what the next scroll steps from.
#
# Reading the value back from a monitor costs ~0.3s, so the last value written
# is cached in $STATE_FILE and the panel is only queried when that is missing.
#
# Usage:
#   display.sh up [step]     raise brightness (default step 20)
#   display.sh down [step]   lower brightness
#   display.sh set <level>   set brightness outright (the bar's slider)
#   display.sh toggle        night mode on / off
#   display.sh night-on      enable night mode if it is off
#   display.sh night-off     disable night mode if it is on
#   display.sh get           print the current brightness; fails with no way to
#                            change it, which is what hides the bar's module

VCP=10
NIGHT_TEMP=3000
DAY_TEMP=6000
BACKLIGHT=/sys/class/backlight

# Private to this user, and gone once their last session ends, which suits what
# these say: how the panel is right now.
RUNTIME="${XDG_RUNTIME_DIR:-$HOME/.cache}/quickshell"
STATE_FILE="$RUNTIME/brightness"
# Existence is the night-mode flag, and that is all it is: the way back out is
# a full panel rather than whatever was on before, so there is nothing to stash
# in it. The bar watches for the file, not for its contents.
NIGHT_FILE="$RUNTIME/night-mode"
LOCK_FILE="$RUNTIME/brightness.lock"

ACTION="${1:-get}"
STEP="${2:-20}"

if compgen -G "$BACKLIGHT/*" >/dev/null; then
  TOOL=brightnessctl
  read_panel() { brightnessctl -m | cut -d, -f4 | tr -d %; }
  # Level 0 is night mode's dimmest, not off: a laptop panel at a true 0 goes
  # black, where a monitor's stays lit.
  write_panel() { brightnessctl -q --min-value=1 set "$1%"; }
else
  TOOL=ddcutil
  # settings.json's displayBus, read here because a keybind runs this without
  # the bar. Naming the bus skips ddcutil's search for the monitor.
  BUS=$(sed -n 's/^ *"displayBus": *"\{0,1\}\([0-9]\+\).*/\1/p' "$(dirname -- "$(realpath -- "$0")")/../settings.json" 2>/dev/null)
  DISPLAY_ARGS=(--display 1)
  [[ -n $BUS ]] && DISPLAY_ARGS=(--bus "$BUS")
  read_panel() {
    ddcutil "${DISPLAY_ARGS[@]}" getvcp "$VCP" 2>/dev/null |
      sed -n 's/.*current value = *\([0-9]\+\).*/\1/p'
  }
  write_panel() { ddcutil "${DISPLAY_ARGS[@]}" setvcp "$VCP" "$1"; }
fi

command -v "$TOOL" >/dev/null || {
  echo "${0##*/}: this screen needs $TOOL" >&2
  exit 1
}

current() {
  local value
  value=$(cat "$STATE_FILE" 2>/dev/null)
  [[ $value =~ ^[0-9]+$ ]] || value=$(read_panel)
  [[ $value =~ ^[0-9]+$ ]] || value=100 # panel unreachable, assume full
  echo "$value"
}

# The write is the slow half, so hyprsunset runs alongside it rather than after.
temperature() { hyprctl hyprsunset temperature "$1" >/dev/null & }

apply() { write_panel "$1" && echo "$1" >"$STATE_FILE"; }

night_on() { [ -e "$NIGHT_FILE" ]; }

mkdir -p "$RUNTIME"

# serialise concurrent scrolls and toggles
exec 9>"$LOCK_FILE"
flock 9

case "$ACTION" in
get)
  current
  exit 0
  ;;
toggle|night-on|night-off)
  # Check under the same lock as manual changes: a stale bar reading must
  # never turn a scheduled enable into a disable (or vice versa).
  [[ $ACTION == night-on ]] && night_on && exit 0
  [[ $ACTION == night-off ]] && ! night_on && exit 0
  # The flag follows the panel: it changes only once the write lands, and the
  # tint goes back if the write fails, so a busy bus can't leave the moon over a
  # lit screen.
  if night_on; then
    temperature "$DAY_TEMP"
    # Full, rather than whatever the panel was on before the night: coming out
    # of night mode happens in a room that got brighter, and the level the
    # screen was on hours ago is not the one it wants back.
    if apply 100; then
      rm -f "$NIGHT_FILE"
    else
      temperature "$NIGHT_TEMP"
      exit 1
    fi
  else
    temperature "$NIGHT_TEMP"
    if apply 0; then
      : >"$NIGHT_FILE"
    else
      temperature "$DAY_TEMP"
      exit 1
    fi
  fi
  exit 0
  ;;
up) VALUE=$(($(current) + STEP)) ;;
down) VALUE=$(($(current) - STEP)) ;;
# A level rather than a step: the slider knows where it wants the panel, and a
# step worked out from its last reading misses whatever a keybind did since.
set)
  [[ $2 =~ ^[0-9]+$ ]] || { echo "set needs a level" >&2; exit 2; }
  VALUE=$2
  ;;
*)
  echo "usage: ${0##*/} up|down|set|toggle|night-on|night-off|get [step|level]" >&2
  exit 2
  ;;
esac

((VALUE > 100)) && VALUE=100
((VALUE < 0)) && VALUE=0

# Scrolling up out of a dark screen means the mode is over; leaving the flag set
# would keep the moon icon and the 3000K tint against a lit panel.
if ((VALUE > 0)) && night_on; then
  rm -f "$NIGHT_FILE"
  temperature "$DAY_TEMP"
fi

apply "$VALUE"
# No signal needed: the bar watches $STATE_FILE and $NIGHT_FILE.

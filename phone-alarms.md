# Phone alarms

QS sends timers and alarms directly to Automate on Android over home Wi-Fi.
Tapping or swiping the phone notification stops that occurrence on both devices.
Dismissing in QS stops all ringing QS timers and their phone alerts.

Follow the [Automate setup tutorial](automate-setup.md) for Android permissions,
background operation, floating alerts, vibration and lock-screen settings.

QS sounds for one minute. The phone loops its selected Android alarm sound for
up to ten minutes. After QS becomes silent, its timer entry stays available to
dismiss while phone delivery is pending or the phone is still ringing. A phone
timeout does not dismiss a newer local alarm.

The flow uses **29 blocks**, including the home Wi-Fi watcher, authentication
and cleanup. It fits Automate's free limit when other running flows use at most
one block. Stopped flows do not consume that running-flow allowance. No purchase
is needed for this configuration.

## Local configuration

Pairing lives in `$XDG_DATA_HOME/quickshell/phone.json`, normally
`~/.local/share/quickshell/phone.json`, with permissions `0600`:

```json
{
  "pairId": "32 random lowercase hex characters",
  "secret": "64 random lowercase hex characters",
  "port": 8080,
  "address": "192.168.50.20",
  "hostname": "phone.local",
  "homeNetworks": [
    {
      "ssid": "Your home SSID",
      "uuid": "NetworkManager saved connection UUID",
      "cidr": "192.168.50.0/24"
    }
  ],
  "volume": 20
}
```

Generate the identifiers with Python's `secrets.token_hex(16)` and
`secrets.token_hex(32)`. Find the active saved connection with
`nmcli -t -f UUID,TYPE,DEVICE connection show --active`. Use its actual SSID,
which can differ from the connection's name. The current generated phone flow
supports one home SSID. QS configuration uses a list so its network checks stay
explicit.

The address, hostname and subnet above are examples. Replace them with your
own network's values; use an empty hostname if the phone has no local hostname.

The address is a starting hint. QS caches the last verified address under
`$XDG_CACHE_HOME/quickshell/phone-address.json`. If it changes, discovery tries
that cache, the configured address, a local hostname and neighbour entries,
then the configured private IPv4 subnet. The subnet must be `/24` or smaller.
Discovery checks the saved NetworkManager UUID and Wi-Fi interface before
probing. It uses one configured port, sixteen concurrent probes and bounded
request timeouts, backing off to once a minute when the phone is absent.

Each candidate must answer a fresh nonce challenge with the paired identifier
and a SHA-256 proof. The challenge contains no shared secret. QS repeats that
identity check before each alarm command. A generic `Android.local` hostname
or an unrelated service on the same port is not accepted as the phone.

## Install or update the phone flow

From the config directory, generate a private import file:

```sh
python3 scripts/automate-flow.py \
  ~/.local/share/quickshell/phone.json \
  '.plans/QS Phone Alarms.flo'
```

The generator targets Automate **1.53.2**, flow format 114. It fixes the phone
limit at 600 seconds. The resulting file contains the pairing secret; keep it
in the locally ignored `.plans/` directory. Do not share it or upload it to a
flow community.

Import that file into Automate, grant the listed storage, location and
background privileges, and start **QS Phone Alarms** once. Use Android's
background location permission so Automate can read the connected SSID. Keep
Automate exempt from battery optimisation. The flow obtains the alarm sound
with **Ringtone get**, so no sound-file picker is needed. Android must have an
alarm sound selected. Volume is the playback percentage, independent of the
phone's Alarm stream volume.

When USB debugging is available, the file can go straight to the phone:

```sh
adb push '.plans/QS Phone Alarms.flo' /sdcard/Download/QS-Phone-Alarms.flo
adb shell am start -a android.intent.action.VIEW \
  -d file:///sdcard/Download/QS-Phone-Alarms.flo \
  -t application/octet-stream \
  -n com.llamalab.automate/.FlowImportActivity
```

Confirm Import and Start on the phone. Dismiss QS alerts and stop/delete the
previous copy before replacing it. Once imported, remove the copy from the
phone's Downloads folder. There is no Drive step.

The home watcher remains running away from home. It starts the listener only
on the configured SSID and stops the listener's alarm workers on departure.
Returning home restarts it automatically, with a three-second delay for address
assignment. Recent occurrence records survive that reconnect, preventing an
old command from restarting an alarm.

## Sound and lock-screen notifications

The phone notification title is "Desktop Alarm". Its message shows the alarm or
timer label sent by QS.

Each alarm reads Android's current default alarm sound. Change that sound in
the phone's alarm-sound settings; the next desktop alarm uses it. This also
changes the default used by other phone alarms.

For a sound used only by this flow, stop the flow, open block 24 (Sound play,
under Camera & sound), and choose a local audio file in Sound URI. Keep Repeat
on and Proceed set to Immediately, save, then start the flow again. A newly
generated import restores the default-alarm-sound setting.

Lock-screen display needs permission both for Automate and its Flow notification
category. On MIUI, open App info, Notifications, Flow, then On the Lock screen.
Choose "Show all notifications and their contents" to show the title and timer
label, or the option to hide contents if preferred. The app-level "Lock screen
notifications" switch must also be on.

Block 28 explicitly selects Automate's built-in Flow notification channel.
Enable floating notifications and vibration for that channel as described in
the [setup tutorial](automate-setup.md#notification-settings). Android controls
the floating banner and initial vibration; they need no extra flow blocks.
Vibration happens once on arrival while the alarm sound keeps looping. Android
may require an unlock for a notification tap.

## Blocks in the generated flow

The flow's expressions and connections are generated automatically. These are
the Android block names and picker categories for inspecting it:

| IDs | Block | Picker category | Purpose |
| --- | --- | --- | --- |
| 1 | Flow beginning | Flow | Start the home watcher |
| 2, 3, 5 | Wi-Fi network connected? | Connectivity | Immediate check, wait for home, watch departure |
| 4, 15, 25 | Fork | Flow | Listener, occurrence worker, timeout worker; stop with parent |
| 6, 22, 27 | Fiber stop | Flow | Home departure, remote stop, timeout |
| 7 | Atomic load | Concurrency | Restore recent occurrence records |
| 8 | Failure catch | Flow | Keep accepting after a malformed or dropped request |
| 9 | HTTP accept | Connectivity | POST `/qs-alarm` on Wi-Fi, configured port; body in a variable |
| 10, 16 | Variable set | General | Decode the request and update the journal |
| 11, 13, 14, 21 | Expression true? | General | Authenticate and dispatch requests; reject stale/duplicate starts |
| 12, 19, 20 | HTTP response | Connectivity | Discovery proof, active state, finished state |
| 17 | Atomic store | Concurrency | Save recent occurrence records |
| 18 | Fiber stopped? | Flow | Determine whether this occurrence is still sounding |
| 23 | Ringtone get | Settings | Read the selected alarm sound |
| 24 | Sound play | Camera & sound | Alarm stream, repeat, proceed immediately |
| 26, 29 | Delay | Date & time | Ring deadline; Wi-Fi settling delay |
| 28 | Notification show | Interface | Flow channel; proceed when dismissed; tap or swipe ends the sound-owning fiber |

Only the dispatcher updates the journal. Each record holds its own sound-owning
fiber, deadline and listener generation. Ending that fiber releases its sound,
notification and timeout child. The journal retains up to 128 occurrences;
when full, it refuses new starts until the oldest record expires. Eviction
also advances a timestamp floor so an evicted occurrence cannot replay.

## Operation and checks

`qs ipc call timer phone` reports configuration/home-network status. Set a timer
normally, or use `qs ipc call timer set '5s Phone test'`.

The protocol uses POST JSON at `/qs-alarm`: `probe`, `ring`, `stop`, and `state`.
Occurrence commands carry a secret, a key made from timer ID and firing time,
and the firing time in seconds. States are `ringing`, `dismissed`, `stopped`,
`timed_out`, `away`, or `unknown`. QS polls active occurrences every two to
three seconds. At the ten-minute deadline, it sends a final stop and keeps the dismissal entry until that request
settles. A thirty-second reconciliation window bounds retries if the phone is
unreachable; no new ring is sent after the deadline. Retries reuse the occurrence
key. One outage produces one failure notification; local timers keep working.

Delivery uses local HTTP on the trusted home LAN. The flow has no cloud-message
blocks or server dependency. The desktop runs no listener or background helper
daemon; `phone-discover.py` exits after each bounded discovery attempt. Automate
itself may make unrelated app, update or telemetry requests.

Focused checks:

```sh
python3 scripts/test-phone-discovery.py
python3 scripts/test-phone-alarms.py
python3 scripts/test-phone-poll.py
python3 scripts/test-timer-wake.py
python3 scripts/test-shell-state.py
```

An Android device passed LAN delivery after an hour locked and idle, phone
notification tap and swipe, remote stop, overlapping alarms, targeted stop,
Wi-Fi departure/rejoin and screen-off delivery. Both dismissal directions
passed against the running QS shell. The production flow also completed a full
ten-minute ring, keeping the silent QS dismissal entry after local sound ended.

A temporary phone IP change, then restoration to DHCP, verified rediscovery
without editing QS configuration. DHCP lease reassignment by the router itself
was not forced.

Delivery and stop also passed with the desktop test client restricted to the
alarm TCP port. This checks the local client path; a physical router-WAN
disconnection remains untested. The flow contains no cloud-message blocks.
Wrong-peer rejection, the saved-network gate, delivery races, deadline cleanup
and polling cadence have isolated tests. Another actual saved SSID has not been
tested on the phone.

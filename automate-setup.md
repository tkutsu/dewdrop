# Set up Android phone alarms with Automate

QS can ring a nearby Android phone over home Wi-Fi. Dismiss the alarm in QS to
stop both devices, or tap or swipe the phone notification to stop that occurrence
on both. The phone sound loops for up to ten minutes; notification vibration
plays once when the alert arrives.

Alarm delivery uses the local network. It needs no LlamaLab server, ntfy server,
Google Drive or cloud messaging account. Automate's own app services may make
unrelated network requests.

All network values in the linked configuration example are illustrative. Keep
your real pairing file and generated flow private.

## Prepare the devices

- Install [Automate](https://llamalab.com/automate/) on Android. The generator
  targets version 1.53.2, flow format 114.
- Install Python 3 and NetworkManager on the QS computer. Connect both devices
  to a trusted home LAN that allows communication between clients. Guest Wi-Fi
  with client isolation will prevent delivery.
- Save the home Wi-Fi connection on each device. The generated flow supports
  one home SSID; the desktop also checks its saved NetworkManager connection.
- Keep Wi-Fi enabled on the phone. Location services must be on where Android
  requires them to expose the connected Wi-Fi name.

The flow has 29 blocks and fits Automate's free allowance of 30 blocks across
running flows. Stop old test flows and duplicate copies before starting it.
Stored, stopped flows do not use that allowance.

## Pair and import the flow

Create the private `phone.json` file using the
[configuration instructions](phone-alarms.md#local-configuration). Fill in the
phone's current Wi-Fi address, the home SSID, the desktop's saved connection
UUID and its private subnet. Generate fresh random pairing identifiers as
described there. The address is a hint: QS searches the configured home subnet
and verifies the paired phone if its address changes.

From the project directory, generate the flow:

```sh
mkdir -p .plans
python3 scripts/automate-flow.py \
  ~/.local/share/quickshell/phone.json \
  '.plans/QS Phone Alarms.flo'
```

Keep `/.plans/` in `.git/info/exclude` and verify it with
`git check-ignore '.plans/QS Phone Alarms.flo'`. The generated file contains the
pairing secret. Do not commit it, share it or upload it to the flow community.
If you use a custom `XDG_DATA_HOME`, use that directory's pairing file instead.

Transfer the file locally and import it through Automate's Import menu. USB
debugging provides a direct route; the
[USB import commands](phone-alarms.md#install-or-update-the-phone-flow) open it
in Automate without Drive. Confirm Import on the phone. Remove the transferred
file from Downloads after importing.

When updating, stop the previous copy before starting the new one. After the
new copy passes the tests below, delete the stopped old copy so only one alarm
flow remains. Regenerating replaces manual changes made in the flow editor.

## Grant the flow's permissions

Open the imported flow and grant the privileges listed on its details screen.
Permission names vary by Android version.

| Setting | Required value and reason |
| --- | --- |
| Notifications | Allow Automate notifications, including Android's notification permission if requested. |
| Location | Allow background location, usually "Allow all the time", so the Wi-Fi watcher can read the SSID while locked. Enable precise location if Android requires it for Wi-Fi identity. |
| Files and media | Grant the storage access requested by this flow for its HTTP request body and sound access. On newer Android releases, follow Automate's requested file-access privilege. |
| Network and Wi-Fi access | Allow local network access if Android prompts. Do not block Automate's Wi-Fi or background data in the phone's app controls. |

Root, accessibility control, notification access to other apps, and a LlamaLab
account are not needed for this flow. USB debugging is only needed for the USB
installation method; it is not part of normal alarm delivery.

## Allow background operation and restart

1. In Android's app settings for Automate, set Battery to Unrestricted or
   disable battery optimization for the app.
2. On Xiaomi/MIUI, set Battery saver to No restrictions and enable Autostart.
   If the phone still removes the app from memory, lock Automate in Recents.
   Other manufacturers may call this Allow background activity, Auto-launch or
   Never sleeping apps.
3. In Automate Settings, enable Run on system startup to resume running flows
   after a phone reboot. Start the flow once before relying on that setting.
   Unlock the phone after reboot, then verify delivery again.
4. Keep Automate's Running notification enabled during setup. It identifies
   the background service. Keep the Errors channel enabled so failures are
   visible.

Start the imported alarm flow once. At home, allow a few seconds for the
listener to start. Away from home, the Wi-Fi watcher remains active but the
listener and its alarm workers stop. They restart on returning to the saved
home network.

See Automate's [background execution and startup FAQ](https://llamalab.com/automate/doc/faq.html)
for manufacturer-specific paths. Do not add a polling or keep-awake loop to
compensate for a missing permission.

## Notification settings

Set both the app permissions and the Flow channel. App-level switches alone
may leave a category hidden or silent.

Open Android Settings, Apps, Automate, Notifications. On MIUI, this is also
available by holding the Automate icon, choosing App info, then Notifications.

| Where | Setting |
| --- | --- |
| Automate app notifications | Enable Show notifications, Floating notifications and Lock screen notifications where those switches exist. |
| Essential, Flow notification category | Enable notifications for the category. Choose High importance, Alerting with Pop on screen, or Floating notifications, depending on the phone's labels. |
| Flow category vibration | Enable Vibration. This produces an initial vibration, not repeating vibration for the full alarm. |
| Flow category lock screen | Choose Show all notifications and their contents to display "Desktop Alarm" and the timer label. Choose Hide contents if you prefer privacy. Do not choose Don't show notifications at all. |
| System lock-screen notifications | Allow notifications globally. A global hide setting can override the app's permission. |
| Do Not Disturb | For the initial test, use a mode that permits notification vibration and floating banners. If you use DND daily, allow Automate or its Flow category through DND where the phone supports it. Alarm audio and notification interruption have separate rules. |

Block 28, Notification show in the Interface picker category, explicitly uses
Automate's built-in Flow channel. Keep Proceed set to When dismissed, Cancellable
on and Ongoing off. Tapping or swiping then ends the fiber that owns the sound.
The Heads-up layout XML field is for a custom visual layout; it does not enable
floating alerts. Leave it blank. See the official
[Notification show documentation](https://llamalab.com/automate/doc/block/notification_show.html).

A floating banner is a brief presentation when Android permits it. The
notification remains available in the notification shade and, with the settings
above, on the lock screen. Android may require an unlock for a tap. Swiping a
lock-screen notification can dismiss it without opening Automate where the
phone permits that gesture.

These settings apply to other flows using the Flow channel too.

## Choose the sound

Select a non-silent default alarm sound in Android's sound or clock settings.
The flow reads that choice each time an alarm starts. This also changes the
default sound used by other phone alarms.

For a sound used only by this flow, stop it, edit block 24, Sound play under
Camera & sound, and choose a local audio file in Sound URI. Keep Repeat on and
Proceed set to Immediately. Save and restart. A regenerated flow restores the
Android default alarm sound.

The `volume` value in `phone.json` is the playback percentage used by the
generated flow. Changing it requires regenerating and importing the flow, or
editing block 24 directly. Lower it for initial tests.

## Verify before relying on it

1. With the phone awake, on home Wi-Fi and outside DND, run
   `qs ipc call timer set '5s Phone test'`. Check the sound, initial vibration
   and floating banner titled "Desktop Alarm".
2. Dismiss the timer in QS. The phone sound and notification should stop.
3. Start another test, lock the phone, and check the lock-screen notification.
   Swipe it away. Both devices should stop within a few seconds.
4. Unplug and leave the phone locked and untouched for at least an hour. Send a
   test before touching the phone. This checks background reachability.
5. Leave and rejoin home Wi-Fi. The listener should recover automatically;
   an old alarm should not restart. Check again after a phone reboot.

If audio plays but vibration or the banner is missing, check the Flow category
and DND first. If the lock-screen card is missing, check the category's lock
screen setting as well as the app and global switches. If nothing arrives,
check that exactly one flow is running, background location is granted, both
devices are on the configured home network, and the flow log has no error.
`qs ipc call timer phone` reports desktop configuration and home-network status;
it does not prove the listener is reachable.

Known limitation: reloading QS currently loses its active phone-alert records.
If a phone alarm is ringing during a reload, dismiss it on the phone or let its
ten-minute limit end it. This setup does not require an internet connection for
alarm delivery; a physical router internet-disconnection test has not been
completed.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth as BlueZ
import qs

// The Bluetooth radio and the devices it knows, straight from BlueZ over
// D-Bus: what blueman-applet ran a whole tray app to say.
//
// Qualified, because this file is itself called Bluetooth and so is the
// module's singleton.
//
// Nothing here can pair a device that asks for a PIN. That needs an agent to
// type it into, and blueman's was the one this machine had. Headphones, pads
// and mice pair without one; for the rest there is bluetoothctl.
Singleton {
    id: root

    readonly property var adapter: BlueZ.Bluetooth.defaultAdapter
    readonly property bool present: !!adapter
    readonly property bool on: adapter?.enabled ?? false
    readonly property bool scanning: adapter?.discovering ?? false

    // Paired devices always, and the ones only seen while scanning once they
    // have a name: an address alone is nothing anyone recognises. Connected
    // first and then by name, so the list only reorders when something
    // connects or pairs, never under the pointer for no reason.
    readonly property var devices: (adapter?.devices.values ?? []).filter(d => d.paired || (root.scanning && d.deviceName !== "")).sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))

    readonly property var connected: devices.filter(d => d.connected)

    // On or off only, as blueman's icon was: which device is connected is
    // the popup's to say, where it is read rather than glimpsed.
    readonly property string icon: on ? Theme.glyph.bluetooth : Theme.glyph.bluetoothOff

    function toggle(): void {
        if (adapter)
            adapter.enabled = !adapter.enabled;
    }

    function scan(wanted: bool): void {
        if (adapter && (adapter.enabled || !wanted))
            adapter.discovering = wanted;
    }

    // One click does whatever the row is waiting for: drop it, bring it
    // back, stop a pairing that is going nowhere, or pair it.
    function activate(device): void {
        if (device.connected)
            device.disconnect();
        else if (device.paired)
            device.connect();
        else if (device.pairing)
            device.cancelPair();
        else
            pair(device);
    }

    // Paired is not connected, and a device that has just been paired is
    // one somebody wants to use. Trusted too, so it can reconnect on its
    // own next time rather than waiting for this popup.
    function pair(device): void {
        const done = () => {
            if (!device.paired)
                return;
            device.pairedChanged.disconnect(done);
            device.trusted = true;
            device.connect();
        };
        device.pairedChanged.connect(done);
        device.pair();
    }

    // 0..100, or -1 for a device that does not report one.
    function battery(device): int {
        return device.batteryAvailable ? Math.round(device.battery * 100) : -1;
    }
}

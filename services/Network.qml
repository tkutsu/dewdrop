pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking as NM
import qs

// Wi-Fi and the cable, from NetworkManager over D-Bus: what nm-applet ran a
// whole tray app to say. Qualified, because Networking has a type called
// Network and so is this file.
Singleton {
    id: root

    readonly property var devices: NM.Networking.devices.values

    readonly property var wifi: devices.find(d => d.type === NM.DeviceType.Wifi) ?? null
    // The one with a cable in, if any does: a dock's port and the board's
    // own are both "wired", and only one of them is ever the connection.
    readonly property var wired: devices.filter(d => d.type === NM.DeviceType.Wired).sort((a, b) => b.connected - a.connected)[0] ?? null

    readonly property bool wifiOn: NM.Networking.wifiEnabled
    readonly property bool wiredUp: wired?.connected ?? false

    // One row per name. NetworkManager lists every access point it hears, and
    // a house with a mesh or a dual-band router is the same network three
    // times over; the one kept is the one in use, or else the loudest.
    // Hidden networks have no name to show and are left out.
    readonly property var networks: {
        // No prototype, so a network called "constructor" is a name like any other.
        const best = Object.create(null);
        for (const n of wifi?.networks.values ?? []) {
            if (!n.name)
                continue;
            const held = best[n.name];
            if (!held || n.connected || (!held.connected && n.signalStrength > held.signalStrength))
                best[n.name] = n;
        }
        // The one in use, then the ones it could switch to without asking,
        // then by strength. Sorted on the bar's five steps rather than the
        // raw figure, which moves every scan and would shuffle the list
        // under the pointer.
        return Object.values(best).sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (root.bars(b.signalStrength) - root.bars(a.signalStrength)) || a.name.localeCompare(b.name));
    }

    readonly property var current: networks.find(n => n.connected) ?? null
    readonly property bool joining: networks.some(n => n.stateChanging && !n.connected)

    // The signal as nm-applet quantised it, and so as the glyph set is cut:
    // five steps, the first of which is no signal at all.
    function bars(strength: real): int {
        const s = strength * 100;
        return s > 80 ? 4 : s > 55 ? 3 : s > 30 ? 2 : s > 5 ? 1 : 0;
    }

    // The cable wins when there is one, the way the system routes. The empty
    // cone while a network comes up is the honest picture of it: no signal
    // yet, and it fills rather than being swapped once there is.
    readonly property string icon: {
        if (wiredUp)
            return Theme.glyph.wired;
        if (current)
            return Theme.glyph.wifiStrength[bars(current.signalStrength)];
        if (joining)
            return Theme.glyph.wifiStrength[0];
        return Theme.glyph.wifiOff;
    }

    readonly property bool online: wiredUp || !!current

    function toggleWifi(): void {
        NM.Networking.wifiEnabled = !NM.Networking.wifiEnabled;
    }

    // Scanning is the radio's time and the battery's, so it runs while
    // someone is looking at the list and not otherwise. Counted, like
    // Sys.watchers, because a popup closing and the next opening can overlap.
    property int watchers: 0
    onWatchersChanged: if (wifi)
        wifi.scannerEnabled = watchers > 0
    onWifiChanged: if (wifi)
        wifi.scannerEnabled = watchers > 0

    function join(network): void {
        // A second tap while it is still coming up or going down would wire a
        // second pair of handlers, and a failure would then ask twice.
        if (network.stateChanging)
            return;
        if (network.connected) {
            network.disconnect();
            return;
        }
        if (!network.known && network.security !== NM.WifiSecurityType.Open) {
            ask(network.name);
            return;
        }
        // A saved network whose password has since changed fails for want
        // of secrets, and that is the moment to ask for the new one.
        function done() {
            network.connectionFailed.disconnect(failed);
            network.connectedChanged.disconnect(joined);
        }
        function failed(reason) {
            done();
            if (reason === NM.ConnectionFailReason.NoSecrets)
                root.ask(network.name);
        }
        function joined() {
            if (network.connected)
                done();
        }
        network.connectionFailed.connect(failed);
        network.connectedChanged.connect(joined);
        network.connect();
    }

    // The password goes through nmcli in a terminal rather than a field in
    // the popup. A popup hanging off the bar takes no keyboard, and the
    // launcher is the one text box the shell keeps; a network is joined for
    // the first time a few times a year.
    function ask(name: string): void {
        OpenPopup.dismiss();
        Quickshell.execDetached(Settings.inTerminal(["nmcli", "--ask", "device", "wifi", "connect", name], "Join " + name + " (floating)", true));
    }

    function forget(network): void {
        network.forget();
    }
}

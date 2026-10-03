import QtQuick
import Quickshell
import Quickshell.Bluetooth as BlueZ
import qs
import qs.services

// The devices, and one click on a row to connect it, drop it or pair it. A
// tick on what is connected, a spinner while something is on its way, and
// the battery at the right edge once there is nothing else to say. The whole
// of blueman is a right click on the bar icon away, for anything this is not.
Popup {
    id: root

    // Wide enough for the header: the title and both of its buttons.
    readonly property int bodyWidth: 264

    spacing: 6

    // Scanning is started from the header and only lasts as long as the popup:
    // nobody is reading the list once it has closed.
    Component.onDestruction: Bluetooth.scan(false)

    function busy(device): bool {
        return device.pairing || device.state === BlueZ.BluetoothDeviceState.Connecting || device.state === BlueZ.BluetoothDeviceState.Disconnecting;
    }

    function detail(device): string {
        if (!device.paired)
            return "pair";
        const battery = Bluetooth.battery(device);
        return device.connected && battery >= 0 ? battery + "%" : "";
    }

    PopupHeader {
        width: root.bodyWidth
        title: "Bluetooth"

        PopupButton {
            framed: true
            glyph: Bluetooth.on ? Theme.glyph.bluetoothOff : Theme.glyph.bluetooth
            label: Bluetooth.on ? "turn off" : "turn on"
            onTapped: Bluetooth.toggle()
        }

        // New devices only turn up while the adapter is looking, and
        // looking is loud on the radio, so it is asked for rather than
        // started every time the popup opens.
        PopupButton {
            framed: true
            visible: Bluetooth.on
            glyph: Theme.glyph.refresh
            label: Bluetooth.scanning ? "stop looking" : "look for devices"
            onTapped: Bluetooth.scan(!Bluetooth.scanning)
        }
    }

    PopupText {
        width: root.bodyWidth
        visible: !Bluetooth.on || Bluetooth.devices.length === 0
        text: !Bluetooth.on ? "Bluetooth is off" : Bluetooth.scanning ? "Looking for devices…" : "No devices paired"
        color: Theme.label2
    }

    Column {
        visible: Bluetooth.on

        Repeater {
            // Diffed, so a device changing state keeps its row (and the
            // pointer on it) rather than rebuilding the list.
            model: ScriptModel {
                values: Bluetooth.devices
            }

            delegate: ChoiceRow {
                id: row

                required property var modelData

                width: root.bodyWidth
                text: modelData.name
                current: modelData.connected
                busy: root.busy(modelData)
                onTapped: Bluetooth.activate(row.modelData)

                PopupText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !forget.visible && text !== ""
                    text: root.detail(row.modelData)
                    color: Theme.label2
                    font.pixelSize: Theme.captionSize
                }

                // Only on the row under the pointer, and only for a device
                // there is something to forget. The row goes with it, so the
                // popup remains open while the device reconnects.
                PopupButton {
                    id: forget

                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.hovered && row.modelData.paired
                    glyph: Theme.glyph.close
                    glyphSize: Theme.captionSize
                    onTapped: {
                        row.modelData.forget();
                    }
                }
            }
        }
    }
}

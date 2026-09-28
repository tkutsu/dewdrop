import QtQuick
import Quickshell
import Quickshell.Bluetooth as BlueZ
import qs
import qs.services

// What blueman-manager was opened for: the devices, and one click on a row to
// connect it, drop it or pair it. A tick marks what is connected; the right
// edge says what is happening to a row, or its battery once there is nothing
// else to say.
Popup {
    id: root

    readonly property int bodyWidth: 240
    readonly property int rowHeight: 24
    // The tick's column, and the air between it and the name.
    readonly property int gutter: 20

    spacing: 6

    // Scanning is started from the foot and only lasts as long as the popup:
    // nobody is reading the list once it has closed.
    Component.onDestruction: Bluetooth.scan(false)

    function status(device): string {
        if (device.pairing)
            return "pairing…";
        if (device.state === BlueZ.BluetoothDeviceState.Connecting)
            return "connecting…";
        if (device.state === BlueZ.BluetoothDeviceState.Disconnecting)
            return "…";
        if (!device.paired)
            return "pair";
        const battery = Bluetooth.battery(device);
        return device.connected && battery >= 0 ? battery + "%" : "";
    }

    PopupText {
        width: root.bodyWidth
        visible: !Bluetooth.on || Bluetooth.devices.length === 0
        text: !Bluetooth.on ? "Bluetooth is off" : Bluetooth.scanning ? "Looking for devices…" : "No devices paired"
        opacity: 0.6
    }

    Column {
        visible: Bluetooth.on

        Repeater {
            // Diffed, so a device changing state keeps its row (and the
            // pointer on it) rather than rebuilding the list.
            model: ScriptModel {
                values: Bluetooth.devices
            }

            delegate: PopupRow {
                id: row

                required property var modelData

                width: root.bodyWidth
                height: root.rowHeight
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: Bluetooth.activate(row.modelData)

                Glyph {
                    x: Math.round((root.gutter - implicitWidth) / 2)
                    height: parent.height
                    visible: row.modelData.connected
                    text: Theme.glyph.check
                    fontSize: Theme.popupTextSize
                }

                PopupText {
                    x: root.gutter
                    anchors.verticalCenter: parent.verticalCenter
                    width: (forget.visible ? forget.x : statusText.x) - x - 6
                    elide: Text.ElideRight
                    text: row.modelData.name
                    opacity: row.modelData.connected ? 1 : 0.7
                }

                PopupText {
                    id: statusText

                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !forget.visible
                    text: root.status(row.modelData)
                    color: Theme.label2
                    font.pixelSize: Theme.captionSize
                }

                // Only on the row under the pointer, and only for a device
                // there is something to forget. The row goes with it, so the
                // popup holds on over the gap it leaves.
                PopupButton {
                    id: forget

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.hovered && row.modelData.paired
                    glyph: Theme.glyph.close
                    onTapped: {
                        root.hold(1500);
                        row.modelData.forget();
                    }
                }
            }
        }
    }

    Rectangle {
        width: root.bodyWidth
        height: Theme.pillBorder
        color: Theme.stroke
    }

    Row {
        spacing: 4

        PopupButton {
            framed: true
            glyph: Bluetooth.on ? Theme.glyph.bluetoothOff : Theme.glyph.bluetooth
            label: Bluetooth.on ? "turn off" : "turn on"
            glyphSize: Theme.captionSize
            textSize: Theme.captionSize
            onTapped: Bluetooth.toggle()
        }

        // New devices only turn up while the adapter is looking, and
        // looking is loud on the radio, so it is asked for rather than
        // started on every hover.
        PopupButton {
            framed: true
            visible: Bluetooth.on
            glyph: Theme.glyph.refresh
            label: Bluetooth.scanning ? "stop looking" : "look for devices"
            glyphSize: Theme.captionSize
            textSize: Theme.captionSize
            onTapped: Bluetooth.scan(!Bluetooth.scanning)
        }
    }
}

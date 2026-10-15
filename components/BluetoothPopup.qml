import QtQuick
import Quickshell
import Quickshell.Bluetooth as BlueZ
import qs
import qs.services

// The devices, and one click on a row to connect it, drop it or pair it. A
// tick on what is connected, a spinner while something is on its way, and
// the battery at the right edge once there is nothing else to say. The
// adapter's switch is at the end of the title, as on the Mac, and the whole
// of blueman is the row at the foot, for anything this is not (a right click
// on the bar icon opens it too).
Popup {
    id: root

    readonly property int bodyWidth: Theme.popupWidth

    // Scanning is started from the header and only lasts as long as the popup:
    // nobody is reading the list once it has closed.
    Component.onDestruction: Bluetooth.scan(false)

    function busy(device): bool {
        return device.pairing || device.state === BlueZ.BluetoothDeviceState.Connecting || device.state === BlueZ.BluetoothDeviceState.Disconnecting;
    }

    function detail(device): string {
        if (!device.paired)
            return "Pair";
        const battery = Bluetooth.battery(device);
        return device.connected && battery >= 0 ? battery + "%" : "";
    }

    PopupHeader {
        width: root.bodyWidth
        title: "Bluetooth"

        // New devices only turn up while the adapter is looking, and
        // looking is loud on the radio, so it is asked for rather than
        // started every time the popup opens. Lit while it looks.
        PopupButton {
            framed: true
            visible: Bluetooth.on
            lit: Bluetooth.scanning
            glyph: Theme.glyph.refresh
            label: "Scan"
            name: Bluetooth.scanning ? "Stop scanning" : "Scan for devices"
            onTapped: Bluetooth.scan(!Bluetooth.scanning)
        }

        PopupButton {
            framed: true
            glyph: Theme.glyph.openApp
            name: "Bluetooth Settings"
            onTapped: {
                OpenPopup.dismiss();
                Quickshell.execDetached(["blueman-manager"]);
            }
        }

        SettingSwitch {
            anchors.verticalCenter: parent.verticalCenter
            name: "Bluetooth"
            checked: Bluetooth.on
            onToggled: Bluetooth.toggle()
        }
    }

    PopupSection {
        width: root.bodyWidth
        visible: Bluetooth.on
        ruled: false
        title: "Devices"
    }

    PopupNote {
        width: root.bodyWidth
        visible: !Bluetooth.on || Bluetooth.devices.length === 0
        text: !Bluetooth.on ? "Bluetooth is off" : Bluetooth.scanning ? "Looking for devices…" : "No devices paired"
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
                // Forget asks twice: the device has to be paired again after.
                // Armed until the pointer leaves the row.
                property bool forgetting: false
                onHoveredChanged: if (!row.hovered)
                    row.forgetting = false

                width: root.bodyWidth
                text: modelData.name
                current: modelData.connected
                busy: root.busy(modelData)
                onTapped: Bluetooth.activate(row.modelData)

                PopupText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !forget.visible && text !== ""
                    text: root.detail(row.modelData)
                    // Low enough to want charging before the next call.
                    readonly property int battery: row.modelData.connected ? Bluetooth.battery(row.modelData) : -1
                    color: battery >= 0 && battery < 20 ? Theme.warn : Theme.label2
                    font.pixelSize: Theme.captionSize
                }

                // Only on the row under the pointer, and only for a device
                // there is something to forget. The row goes with it, so the
                // popup remains open while the device reconnects.
                PopupButton {
                    id: forget

                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.hovered && row.modelData.paired
                    name: (row.forgetting ? "Confirm forget " : "Forget ") + row.text
                    glyph: row.forgetting ? Theme.glyph.check : Theme.glyph.close
                    glyphSize: Theme.captionSize
                    warn: row.forgetting
                    onTapped: {
                        if (row.forgetting)
                            row.modelData.forget();
                        row.forgetting = !row.forgetting;
                    }
                }
            }
        }
    }
}

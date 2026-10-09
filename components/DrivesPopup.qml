import QtQuick
import Quickshell
import qs
import qs.services

// Each drive with how full it is, a click on it to open it in the file
// manager (or mount it, if nothing on it is), and the eject at its right edge
// to take it out safely. Under them, the batteries of wired things that have
// one.
Popup {
    id: root

    readonly property int bodyWidth: 264

    spacing: 6

    // Decimal, as the size printed on the stick is.
    function bytes(n: real): string {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        while (n >= 1000 && i < units.length - 1) {
            n /= 1000;
            i++;
        }
        return `${n.toFixed(n < 10 && i > 0 ? 1 : 0)} ${units[i]}`;
    }

    PopupHeader {
        width: root.bodyWidth
        title: "Devices"
    }

    Repeater {
        model: ScriptModel {
            values: Drives.drives
            objectProp: "disk"
        }

        delegate: PopupRow {
            id: row

            required property var modelData
            readonly property bool mounted: modelData.total > 0
            readonly property bool ejecting: !!Drives.ejecting[modelData.disk]

            name: row.modelData.name
            width: root.bodyWidth
            height: 40
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: Drives.open(row.modelData)

            PopupText {
                id: name
                x: 6
                y: 5
                width: eject.x - x - 8
                text: row.modelData.name
                elide: Text.ElideRight
                font.pixelSize: Theme.captionSize
                font.weight: Font.DemiBold
            }

            PopupText {
                anchors.right: eject.left
                anchors.rightMargin: 8
                anchors.baseline: name.baseline
                text: row.mounted ? `${root.bytes(row.modelData.used)} / ${root.bytes(row.modelData.total)}` : `${root.bytes(row.modelData.size)} · not mounted`
                color: Theme.label2
                font.pixelSize: Theme.captionSize
            }

            // How full it is, as the system popup's memory and disks are.
            Rectangle {
                x: 6
                y: 26
                width: eject.x - x - 8
                height: 3
                color: Theme.meterTrack
                visible: row.mounted

                Rectangle {
                    width: Math.round(parent.width * Math.min(1, row.modelData.used / row.modelData.total))
                    height: parent.height
                    color: row.modelData.used / row.modelData.total > 0.9 ? Theme.warn : Theme.fg
                }
            }

            PopupButton {
                id: eject
                name: "Eject " + row.modelData.name

                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                visible: !row.ejecting
                glyph: Theme.glyph.eject
                onTapped: Drives.eject(row.modelData)
            }

            Spinner {
                anchors.centerIn: eject
                visible: row.ejecting
            }
        }
    }

    PopupText {
        width: root.bodyWidth
        leftPadding: 6
        visible: Drives.batteries.length > 0
        text: "Batteries"
        color: Theme.label2
        font.pixelSize: Theme.captionSize
    }

    Repeater {
        model: ScriptModel {
            values: Drives.batteries
        }

        delegate: ChoiceRow {
            id: battery

            required property var modelData
            readonly property int percent: Math.round(modelData.percentage * 100)

            width: root.bodyWidth
            text: modelData.model || "Battery"

            PopupText {
                anchors.verticalCenter: parent.verticalCenter
                text: battery.percent + "%"
                color: battery.percent < 20 ? Theme.warn : Theme.label2
                font.pixelSize: Theme.captionSize
            }
        }
    }
}

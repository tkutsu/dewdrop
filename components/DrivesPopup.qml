import QtQuick
import Quickshell
import qs
import qs.services

// Each drive with how much is on it, a click on it to open it in the file
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

        // The grid the batteries below and the other lists use: the tick on
        // a drive that is mounted, its size at the right, then the eject.
        delegate: ChoiceRow {
            id: row

            required property var modelData
            readonly property bool mounted: modelData.total > 0

            width: root.bodyWidth
            text: modelData.name
            current: row.mounted
            busy: !!Drives.ejecting[modelData.disk]
            onTapped: Drives.open(row.modelData)

            PopupText {
                anchors.verticalCenter: parent.verticalCenter
                text: row.mounted ? `${root.bytes(row.modelData.used)} / ${root.bytes(row.modelData.total)}` : root.bytes(row.modelData.size)
                // Nearly full, where the meter used to turn.
                color: row.mounted && row.modelData.used / row.modelData.total > 0.9 ? Theme.warn : Theme.label2
                font.pixelSize: Theme.captionSize
            }

            PopupButton {
                anchors.verticalCenter: parent.verticalCenter
                name: "Eject " + row.text
                glyph: Theme.glyph.eject
                glyphSize: Theme.captionSize
                onTapped: Drives.eject(row.modelData)
            }
        }
    }

    PopupText {
        width: root.bodyWidth
        leftPadding: Theme.popupInset
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

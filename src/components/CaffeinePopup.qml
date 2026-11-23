import QtQuick
import qs.src.core
import qs.src.services

// Caffeine: the switch, and how long a turn on holds the screen awake, on a
// track of set lengths from an hour to always. A new length while it is on
// counts from then.
Popup {
    id: root

    readonly property int bodyWidth: Theme.popupWidth

    PopupHeader {
        width: root.bodyWidth
        title: "Caffeine"

        SettingSwitch {
            anchors.verticalCenter: parent.verticalCenter
            name: "Caffeine"
            checked: Caffeine.active
            onToggled: Caffeine.toggle()
        }
    }

    PopupSection {
        width: root.bodyWidth
        ruled: false
        title: "Keep Awake"
    }

    // The lengths, shortest first, in minutes; 0 holds until turned off.
    // Nothing under an hour: the idle timeout covers that much by itself.
    readonly property var stops: [
        { minutes: 60, label: "1 Hour" }, { minutes: 120, label: "2 Hours" },
        { minutes: 180, label: "3 Hours" }, { minutes: 360, label: "6 Hours" },
        { minutes: 720, label: "12 Hours" }, { minutes: 1440, label: "1 Day" },
        { minutes: 0, label: "Always" }
    ]
    readonly property int stop: Math.max(0, root.stops.findIndex(stop => stop.minutes === Caffeine.minutes))
    readonly property real stepSize: 1 / (root.stops.length - 1)

    // The track and the length it is on, as Display has the brightness.
    Row {
        id: row

        width: root.bodyWidth
        leftPadding: Theme.popupInset
        rightPadding: Theme.popupInset
        spacing: 10

        Slider {
            width: root.bodyWidth - Theme.popupInset * 2 - row.spacing - readout.width
            anchors.verticalCenter: parent.verticalCenter
            name: "Keep awake"
            value: root.stop * root.stepSize
            wheelStep: root.stepSize
            wheelSnap: true
            // Snapped to the nearest stop; one moved to counts from then.
            onMoved: value => {
                const stop = Math.round(value / root.stepSize);
                if (stop !== root.stop)
                    Caffeine.choose(root.stops[stop].minutes);
            }
        }

        PopupText {
            id: readout

            anchors.verticalCenter: parent.verticalCenter
            // As wide as the longest, so the track holds still.
            width: Math.ceil(longest.advanceWidth)
            horizontalAlignment: Text.AlignRight
            text: root.stops[root.stop].label

            TextMetrics {
                id: longest

                font: readout.font
                text: "12 Hours"
            }
        }
    }

    PopupNote {
        width: root.bodyWidth
        visible: Caffeine.endsAt !== ""
        text: `Turns off at ${Caffeine.endsAt}`
    }
}

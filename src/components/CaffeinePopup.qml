import QtQuick
import qs.src.core
import qs.src.services

// Caffeine: the switch, and how long a turn on holds the screen awake. A new
// length while it is on counts from then.
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

    Item {
        width: root.bodyWidth
        height: choice.height

        SettingChoice {
            id: choice

            x: Theme.popupInset
            setting: ({
                title: "Keep awake",
                options: [{ value: 0, label: "Always" }, { value: 60, label: "1 Hour" }, { value: 120, label: "2 Hours" }],
                get: () => Caffeine.minutes,
                set: minutes => Caffeine.choose(minutes)
            })
        }
    }

    PopupNote {
        width: root.bodyWidth
        visible: Caffeine.endsAt !== ""
        text: `Turns off at ${Caffeine.endsAt}`
    }
}

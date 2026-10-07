import QtQuick
import qs

// On or off: a track with a knob that slides to the lit end. The row it
// sits in takes the click (SettingRow), so this only draws.
Item {
    id: root

    property var setting: null
    readonly property bool on: root.setting?.get() === true

    implicitWidth: 28
    implicitHeight: 16

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.on ? Theme.label : Theme.sliderTrack

        Behavior on color {
            ColorAnimation {
                duration: Theme.fadeMs
            }
        }
    }

    Rectangle {
        width: root.height - 4
        height: width
        radius: width / 2
        y: 2
        x: root.on ? root.width - width - 2 : 2
        color: root.on ? Theme.calTodayText : Theme.fg

        Behavior on x {
            NumberAnimation {
                duration: Theme.fadeMs
                easing.type: Easing.InOutCubic
            }
        }
    }
}

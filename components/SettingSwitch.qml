import QtQuick
import qs

// On or off: a track with a knob that slides to the lit end. In a SettingRow
// the row takes the click, so this only draws. Standing alone, as a popup's
// master switch at the end of its header (Wi-Fi, Bluetooth), it says its state
// through `checked` and takes its own press and the keys.
Item {
    id: root

    property var setting: null
    property bool checked: false
    property string name: ""
    readonly property bool standalone: root.setting === null
    readonly property bool on: root.standalone ? root.checked : root.setting.get() === true

    signal toggled

    // The keys (Popup.qml); without a `keyed` the popup rings it.
    readonly property var keyPress: root.standalone ? () => root.toggled() : null

    Accessible.role: Accessible.CheckBox
    Accessible.name: root.name
    Accessible.checked: root.on
    Accessible.ignored: !root.standalone
    Accessible.onPressAction: if (root.standalone && root.enabled && root.visible)
        root.toggled()
    Accessible.onToggleAction: if (root.standalone && root.enabled && root.visible)
        root.toggled()

    implicitWidth: 28
    implicitHeight: 16

    TapHandler {
        enabled: root.standalone
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.toggled()
    }

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
        color: root.on ? Theme.switchKnobOn : Theme.fg

        Behavior on color {
            ColorAnimation {
                duration: Theme.fadeMs
            }
        }

        Behavior on x {
            NumberAnimation {
                duration: Theme.fadeMs
                easing.type: Easing.InOutCubic
            }
        }
    }
}

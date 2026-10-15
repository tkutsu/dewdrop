import QtQuick
import qs

// On or off: a knob on a bare track, and white light that pours along the
// track behind it as it slides to the lit end and drains as it comes back, so
// a switch caught mid-spring is part lit and the overshoot shows in the light.
// The knob is one object throughout: white on the bare track, the glass's own
// near-black on the lit one, and it stretches towards where it will go while
// a press is held. In a SettingRow the row takes the click and lends its
// press (`held`), so this only draws. Standing alone, as a popup's master
// switch at the end of its header (Wi-Fi, Bluetooth), it says its state
// through `checked` and takes its own press and the keys.
Item {
    id: root

    property var setting: null
    property bool checked: false
    property string name: ""
    readonly property bool standalone: root.setting === null
    readonly property bool on: root.standalone ? root.checked : root.setting.get() === true
    property bool held: tap.pressed

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

    // How far along the knob is, 0 off to 1 on; past either end mid-spring.
    property real position: root.on ? 1 : 0
    readonly property real lit: Math.min(1, Math.max(0, root.position))

    Behavior on position {
        SpringAnimation {
            spring: Theme.switchSpring
            damping: Theme.switchDamping
            epsilon: 0.002
        }
    }

    property real stretch: root.held ? 1 : 0

    Behavior on stretch {
        SpringAnimation {
            spring: Theme.keyMarkSpring
            damping: Theme.keyMarkDamping
            epsilon: 0.01
        }
    }

    TapHandler {
        id: tap

        enabled: root.standalone
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.toggled()
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.sliderTrack
    }

    // The light, as far as the knob's trailing edge has come. Faded in over
    // the first third of the way, so it never shows round an off knob.
    Rectangle {
        height: root.height
        width: Math.min(root.width, knob.x + knob.width + 2)
        radius: height / 2
        color: Theme.label
        opacity: Math.min(1, root.position * 3)
        visible: opacity > 0
    }

    // A pixel of shadow under the knob, to stand it on the track.
    Rectangle {
        x: knob.x
        y: knob.y + 1
        width: knob.width
        height: knob.height
        radius: knob.radius
        color: Theme.shadow
    }

    Rectangle {
        id: knob

        width: root.height - 4 + 5 * root.stretch
        height: root.height - 4
        radius: height / 2
        y: 2
        x: 2 + root.position * (root.width - 4 - width)
        color: Theme.mix(Theme.switchKnob, Theme.solid, root.lit)
    }
}

import QtQuick
import QtQuick.Shapes
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

    // Cut out the knob so these translucent tones swap without stacking.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillRule: ShapePath.OddEvenFill
            fillColor: root.on ? Theme.selectionStrong : Theme.well

            Behavior on fillColor {
                ColorAnimation {
                    duration: Theme.fadeMs
                }
            }

            PathRectangle {
                width: root.width
                height: root.height
                radius: root.height / 2
            }

            PathRectangle {
                x: knob.x
                y: knob.y
                width: knob.width
                height: knob.height
                radius: knob.radius
            }
        }
    }

    Rectangle {
        id: knob

        width: root.height - 4
        height: width
        radius: width / 2
        y: 2
        x: root.on ? root.width - width - 2 : 2
        color: root.on ? Theme.well : Theme.selectionStrong

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

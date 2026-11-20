pragma ComponentBehavior: Bound

import QtQuick
import qs.src.core
import qs.src.services

// Sleep, Restart and Shut Down along the foot of the lock screen: a round button
// each, its name under it. They
// run what the launcher's power rows run (Power.qml). Restart and Shut Down
// end whatever is open, so they arm on the first press and act on the second,
// and the pointer leaving one disarms it; Sleep goes at once, and the lock is
// still up when the machine wakes.
Row {
    id: root

    // The key of the armed action, or "".
    property string armed: ""
    readonly property var actions: ["suspend", "reboot", "shutdown"]
        .map(key => Power.actions.find(action => action.key === key))
        .filter(Boolean)
    readonly property var glyphs: ({
            suspend: Theme.glyph.lockSleep,
            reboot: Theme.glyph.lockRestart,
            shutdown: Theme.glyph.lockShutDown
        })

    spacing: 12

    Repeater {
        model: root.actions

        Column {
            id: button

            required property var modelData
            readonly property bool armed: root.armed === button.modelData.key

            // One width each, so the circles stand evenly whatever their names.
            width: 80
            spacing: 8

            Accessible.role: Accessible.Button
            Accessible.name: (button.armed ? "Confirm " : "") + button.modelData.name
            Accessible.onPressAction: button.press()

            function press(): void {
                if (button.modelData.confirm && !button.armed) {
                    root.armed = button.modelData.key;
                    return;
                }
                root.armed = "";
                Power.run(button.modelData.arg);
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 44
                height: 44
                radius: width / 2
                color: button.armed ? Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.24)
                    : hover.hovered ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.14)
                border.width: 1
                border.color: Theme.stroke
                Behavior on color {
                    ColorAnimation { duration: Theme.fadeMs }
                }

                Glyph {
                    anchors.centerIn: parent
                    text: button.armed ? Theme.glyph.powerConfirm : root.glyphs[button.modelData.key] ?? button.modelData.glyph
                    fontSize: 22
                    color: button.armed ? Theme.warn : Theme.fg
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: button.modelData.name
                color: button.armed ? Theme.warn : Theme.fg
                font.family: Theme.bodyFont
                font.pixelSize: Theme.captionSize
                font.weight: Font.DemiBold
            }

            HoverHandler {
                id: hover
                onHoveredChanged: if (!hover.hovered && button.armed)
                    root.armed = ""
            }
            TapHandler {
                onTapped: button.press()
            }
        }
    }
}

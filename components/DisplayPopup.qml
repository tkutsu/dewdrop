import QtQuick
import qs
import qs.services

// The night mode module's popup, laid out like Control Center's display
// module: the brightness on a track the pointer can grab, then night mode as
// a section with Off, On and Auto across its first row, and the schedule's
// hours opening under them on Auto.
Popup {
    id: root

    readonly property real bodyWidth: Theme.popupWidth

    PopupHeader {
        width: root.bodyWidth
        title: "Display"
    }

    // The brightness track and percentage.
    Row {
        id: row

        width: root.bodyWidth
        leftPadding: Theme.popupInset
        rightPadding: Theme.popupInset
        spacing: 10

        Slider {
            width: root.bodyWidth - Theme.popupInset * 2 - row.spacing - 34
            anchors.verticalCenter: parent.verticalCenter
            name: "Brightness"
            value: NightMode.brightness / 100
            wheelStep: 0.05
            onMoved: value => NightMode.setBrightness(value * 100)
        }

        PopupText {
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            horizontalAlignment: Text.AlignRight
            text: NightMode.brightness + "%"
        }
    }

    Column {
        width: root.bodyWidth

        PopupSection {
            width: root.bodyWidth
            title: "Night Mode"
        }

        // Off, On and Auto across the row, under the heading.
        Item {
            width: root.bodyWidth
            height: choice.y + choice.height

            SettingChoice {
                id: choice

                x: Theme.popupInset
                y: Theme.popupSpacing
                width: root.bodyWidth - Theme.popupInset * 2
                setting: ({
                    title: "Night mode",
                    options: [{ value: "off", label: "Off" }, { value: "on", label: "On" }, { value: "auto", label: "Auto" }],
                    get: () => NightMode.mode,
                    set: mode => NightMode.setMode(mode)
                })
            }
        }

        // The hours, unfolding the way Wallpaper's framing does. They carry
        // their own air, so a folded schedule leaves none behind.
        Item {
            readonly property bool shown: NightMode.mode === "auto"

            width: root.bodyWidth
            height: shown ? hours.y + hours.height : 0
            opacity: shown ? 1 : 0
            visible: height > 0
            clip: true

            Behavior on height {
                NumberAnimation {
                    duration: Theme.fadeMs
                    easing.type: Easing.InOutQuad
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.fadeMs
                }
            }

            Row {
                id: hours

                y: Theme.popupSpacing
                leftPadding: Theme.popupInset
                spacing: 8

                TimeDial {
                    id: start
                    name: "Night mode start"
                    minute: NightMode.startMinute
                    other: end.draftMinute
                    onEdited: NightMode.queueSchedule(start.value, end.value)
                }

                PopupText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "to"
                    color: Theme.label2
                }

                TimeDial {
                    id: end
                    name: "Night mode end"
                    minute: NightMode.endMinute
                    other: start.draftMinute
                    onEdited: NightMode.queueSchedule(start.value, end.value)
                }
            }
        }
    }

    component TimeDial: Rectangle {
        id: dial
        property string name: ""
        property int minute: 0
        property int draftMinute: minute
        property int other: -1
        readonly property string value: NightMode.formatTime(draftMinute)
        signal edited
        width: 70
        height: 40
        radius: Theme.selectionRadius
        color: Theme.selection
        border.width: Theme.pillBorder
        border.color: Theme.stroke
        onMinuteChanged: draftMinute = minute

        // Wrap through midnight in half-hour steps and queue the range for
        // saving. Hop over the other end: an empty range would never save,
        // and the dials would show a schedule that isn't the one in force.
        function step(direction) {
            draftMinute = (draftMinute + direction * 30 + 1440) % 1440;
            if (draftMinute === other)
                draftMinute = (draftMinute + direction * 30 + 1440) % 1440;
            edited();
        }

        PopupText {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - arrows.width
            text: dial.value
            font.family: Theme.monoFont
            font.pixelSize: Theme.captionSize
            horizontalAlignment: Text.AlignHCenter
        }

        Column {
            id: arrows
            anchors.right: parent.right
            TimeArrow { name: "Increase " + dial.name.toLowerCase(); objectName: "increase"; direction: 1; onStepped: dial.step(direction) }
            TimeArrow { name: "Decrease " + dial.name.toLowerCase(); objectName: "decrease"; direction: -1; onStepped: dial.step(direction) }
        }
    }

    component TimeArrow: Item {
        id: arrow
        property string name: ""
        Accessible.role: Accessible.Button
        Accessible.name: arrow.name
        Accessible.onPressAction: if (arrow.enabled && arrow.visible)
            arrow.stepped()
        readonly property var keyPress: () => arrow.stepped()
        property int direction: 1
        property double heldSince: 0
        property real repeatDelay: 450
        signal stepped
        width: 22
        height: 20

        Rectangle {
            anchors.fill: parent
            radius: Theme.selectionRadius
            color: area.pressed && area.containsMouse ? Theme.selectionStrong
                : area.containsMouse ? Theme.selection : "transparent"
        }

        PopupText {
            anchors.centerIn: parent
            text: arrow.direction > 0 ? "\u25b4" : "\u25be"
            color: area.containsMouse ? Theme.fg : Theme.label2
            font.pixelSize: Theme.popupTextSize
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            preventStealing: true
            onPressed: {
                arrow.heldSince = Date.now();
                arrow.repeatDelay = 450;
                arrow.stepped();
            }
        }

        // After the initial pause, accelerate toward one half-hour step every 60 ms.
        Timer {
            interval: arrow.repeatDelay
            repeat: true
            running: area.pressed && area.containsMouse && arrow.visible
            onTriggered: {
                arrow.stepped();
                arrow.repeatDelay = Math.max(60, Math.round(240 * Math.exp(-(Date.now() - arrow.heldSince) / 1600)));
            }
        }
    }
}

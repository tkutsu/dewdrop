import QtQuick
import qs.src.core
import qs.src.services

// The night mode module's popup: the brightness on a track the pointer can grab, then night mode as
// a section with a mode picker and editable hours for a custom schedule.
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
            wheelSnap: true
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

        // The dimming works without it; the warmth is hyprsunset's.
        NeedsNote {
            width: root.bodyWidth
            topPadding: Theme.popupSpacing
            feature: "Night tint"
            programs: ["hyprsunset"]
        }

        // Four modes use the shared dropdown rather than a crowded capsule.
        Item {
            width: root.bodyWidth
            height: choice.y + choice.height

            SettingDropdown {
                id: choice

                x: Theme.popupInset
                y: Theme.popupSpacing
                setting: ({
                    title: "Night mode",
                    options: [{ value: "off", label: "Off" }, { value: "on", label: "On" },
                        { value: "auto", label: "Auto" }, { value: "custom", label: "Custom" }],
                    get: () => NightMode.mode,
                    set: mode => NightMode.setMode(mode)
                })
            }
        }

        PopupNote {
            width: root.bodyWidth
            visible: NightMode.mode === "auto"
            topPadding: Theme.popupSpacing * 2
            text: NightMode.solar
                ? `Sunset at ${Settings.sayTime(new Date(NightMode.solar.sunset * 1000))}\nSunrise at ${Settings.sayTime(new Date(NightMode.solar.sunrise * 1000))}`
                : NightMode.solarInfo
        }

        // The hours, unfolding the way Wallpaper's framing does. They carry
        // their own air, so a folded schedule leaves none behind.
        Item {
            readonly property bool shown: NightMode.mode === "custom"

            width: root.bodyWidth
            height: shown ? hours.y + hours.height : 0
            opacity: shown ? 1 : 0
            visible: height > 0
            clip: true

            Behavior on height {
                enabled: root.animateContents
                NumberAnimation {
                    duration: Theme.fadeMs
                    easing.type: Easing.InOutQuad
                }
            }

            Behavior on opacity {
                enabled: root.animateContents
                NumberAnimation {
                    duration: Theme.fadeMs
                }
            }

            Row {
                id: hours

                y: Theme.popupSpacing * 2
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
        // What is saved (always 24h); what shows follows the Hour Format.
        readonly property string value: NightMode.formatTime(draftMinute)
        signal edited
        // Wide enough for the widest time it can show, 12:30 PM or 12:30.
        width: Math.max(70, Math.ceil(widest.advanceWidth) + arrows.width + 8)
        height: 28
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

        TextMetrics {
            id: widest
            font: shown.font
            text: Settings.sayHourMinute(12, 30)
        }

        PopupText {
            id: shown
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - arrows.width
            textFormat: Text.RichText
            text: Settings.timeMarkup(Settings.hourDisplay(new Date(2000, 0, 1, Math.floor(dial.draftMinute / 60), dial.draftMinute % 60)), font.pixelSize)
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
        height: 14

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

import QtQuick
import qs

// Options in a capsule, as Apple's segmented control: the chosen one sits
// under the glass mark the workspaces and the power menu use, and a new pick
// flows it across on the switch spring. Each option takes its label's room;
// given a wider row, they share out the rest evenly.
Rectangle {
    id: root

    property var setting: null
    readonly property var current: root.setting?.get()
    readonly property var options: root.setting?.options ?? []
    readonly property int chosenIndex: root.options.findIndex(option => option.value === root.current)
    // itemAt() is not a binding's dependency; the count is, so the chosen one
    // is found again once the options are built.
    readonly property Item chosen: root.chosenIndex >= 0 && root.chosenIndex < buttons.count ? buttons.itemAt(root.chosenIndex) : null

    // The mark rests until a pick moves it, so it doesn't flow in from the
    // edge while the options are first laid out.
    function choose(value) {
        mark.placed = true;
        if (value !== root.current)
            root.setting.set(value);
    }

    readonly property real naturalWidth: cells.children.reduce((total, child) => total + (child.natural ?? 0), Theme.markInset * 2)
    readonly property real spare: root.options.length ? Math.max(0, (root.width - root.naturalWidth) / root.options.length) : 0

    implicitWidth: root.naturalWidth
    implicitHeight: 22
    radius: height / 2
    color: Theme.well

    FlowMark {
        id: mark

        anchors.fill: parent
        visible: root.chosen !== null
        held: root.chosen?.held ?? false
        spring: Theme.switchSpring
        damping: Theme.switchDamping
        slabHeight: root.height
        wantLeft: root.chosen ? cells.x + root.chosen.x : 0
        wantRight: root.chosen ? cells.x + root.chosen.x + root.chosen.width : 0
        atFirst: root.chosenIndex === 0
        atLast: root.chosenIndex === root.options.length - 1
        wallLeft: Theme.pillBorder
        wallRight: root.width - Theme.pillBorder
    }

    Row {
        id: cells

        x: Theme.markInset
        height: root.height

        Repeater {
            id: buttons

            model: root.options

            Item {
                id: option

                required property var modelData
                readonly property bool isChosen: option === root.chosen
                readonly property bool held: tap.pressed
                readonly property real natural: label.implicitWidth + 20

                Accessible.role: Accessible.RadioButton
                Accessible.name: root.setting.title + ": " + option.modelData.label
                Accessible.checked: option.isChosen
                Accessible.onPressAction: if (option.enabled && option.visible)
                    root.choose(option.modelData.value)
                Accessible.onToggleAction: if (option.enabled && option.visible)
                    root.choose(option.modelData.value)
                // A popup's keys (Popup.qml) reach each option.
                readonly property var keyPress: () => root.choose(option.modelData.value)

                width: Math.round(option.natural + root.spare)
                height: root.height

                PopupText {
                    id: label

                    anchors.centerIn: parent
                    text: option.modelData.label
                    font.pixelSize: Theme.captionSize
                    color: option.isChosen ? Theme.fg : hover.hovered ? Theme.label : Theme.label2

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.fadeMs
                        }
                    }
                }

                HoverHandler {
                    id: hover
                }

                TapHandler {
                    id: tap
                    onTapped: root.choose(option.modelData.value)
                }
            }
        }
    }
}

import QtQuick
import qs

// Options in a capsule with the same plain fill and timed slide as a switch.
// Each option takes its label's room; in a wider row they share the rest evenly.
Rectangle {
    id: root

    property var setting: null
    readonly property var current: root.setting?.get()
    readonly property var options: root.setting?.options ?? []
    readonly property int chosenIndex: root.options.findIndex(option => option.value === root.current)
    // itemAt() is not a binding's dependency; the count is, so the chosen one
    // is found again once the options are built.
    readonly property Item chosen: root.chosenIndex >= 0 && root.chosenIndex < buttons.count ? buttons.itemAt(root.chosenIndex) : null

    function choose(value) {
        if (value !== root.current)
            root.setting.set(value);
    }

    readonly property real naturalWidth: cells.children.reduce((total, child) => total + (child.natural ?? 0), Theme.markInset * 2)
    readonly property real spare: root.options.length ? Math.max(0, (root.width - root.naturalWidth) / root.options.length) : 0

    implicitWidth: root.naturalWidth
    implicitHeight: 22
    radius: height / 2
    color: Theme.well

    Rectangle {
        id: mark

        // Place the initial selection directly, then animate later changes.
        property bool placed: false
        onVisibleChanged: if (visible && !placed)
            Qt.callLater(() => { if (mark.visible) mark.placed = true; })

        visible: root.chosen !== null
        x: root.chosen ? cells.x + root.chosen.x : Theme.markInset
        y: Theme.markInset
        width: root.chosen?.width ?? 0
        height: root.height - Theme.markInset * 2
        radius: height / 2
        color: Theme.selectionStrong

        Behavior on x {
            enabled: mark.placed
            NumberAnimation {
                duration: Theme.fadeMs
                easing.type: Easing.InOutCubic
            }
        }

        Behavior on width {
            enabled: mark.placed
            NumberAnimation {
                duration: Theme.fadeMs
                easing.type: Easing.InOutCubic
            }
        }
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
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.choose(option.modelData.value)
                }
            }
        }
    }
}

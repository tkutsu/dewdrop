import QtQuick
import qs

// Options in a well, wrapping when the row is narrow.
Rectangle {
    id: root

    property var setting: null
    readonly property var current: root.setting?.get()

    implicitWidth: options.children.reduce((total, child) => total + (child.modelData ? child.width : 0), 4)
    implicitHeight: Math.max(22, options.implicitHeight + 4)
    radius: Theme.selectionRadius + 2
    color: Theme.well

    Flow {
        id: options

        x: 2
        y: 2
        width: parent.width - 4

        Repeater {
            model: root.setting?.options ?? []

            Rectangle {
                id: option

                required property var modelData
                readonly property bool chosen: modelData.value === root.current

                Accessible.role: Accessible.RadioButton
                Accessible.name: root.setting.title + ": " + option.modelData.label
                Accessible.checked: option.chosen
                Accessible.onPressAction: if (!option.chosen && option.enabled && option.visible)
                    root.setting.set(option.modelData.value)
                Accessible.onToggleAction: if (!option.chosen && option.enabled && option.visible)
                    root.setting.set(option.modelData.value)
                // A popup's keys (Popup.qml) reach each option.
                readonly property var keyPress: () => {
                    if (!option.chosen)
                        root.setting.set(option.modelData.value);
                }

                width: label.implicitWidth + 20
                height: 18
                radius: Theme.selectionRadius
                color: option.chosen ? Theme.selectionStrong : hover.hovered ? Theme.selection : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.fadeMs
                    }
                }

                PopupText {
                    id: label

                    anchors.centerIn: parent
                    text: option.modelData.label
                    font.pixelSize: Theme.captionSize
                    font.weight: option.chosen ? Font.DemiBold : Font.Normal
                    color: option.chosen ? Theme.fg : Theme.label2
                }

                HoverHandler {
                    id: hover
                }

                TapHandler {
                    onTapped: if (!option.chosen)
                        root.setting.set(option.modelData.value)
                }
            }
        }
    }
}

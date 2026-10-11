import QtQuick
import qs

// One of a few: the options side by side in a well, the one in force lifted
// out of it. An option with a swatch is drawn as a dot of that colour rather
// than named.
Rectangle {
    id: root

    property var setting: null
    readonly property var current: root.setting?.get()

    implicitWidth: options.implicitWidth + 4
    implicitHeight: 22
    radius: Theme.selectionRadius + 2
    color: Theme.well

    Row {
        id: options

        x: 2
        y: 2
        height: parent.height - 4

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

                width: option.modelData.swatch ? parent.height + 4 : label.implicitWidth + 20
                height: parent.height
                radius: Theme.selectionRadius
                color: option.chosen ? Theme.selectionStrong : hover.hovered ? Theme.selection : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.fadeMs
                    }
                }

                Rectangle {
                    visible: !!option.modelData.swatch
                    anchors.centerIn: parent
                    width: 12
                    height: 12
                    radius: 6
                    color: option.modelData.swatch ?? "transparent"
                    border.width: 1
                    border.color: Theme.stroke
                }

                PopupText {
                    id: label

                    visible: !option.modelData.swatch
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

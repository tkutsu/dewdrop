import QtQuick
import qs

// One setting in the settings window: what it is on the left, a line or two
// on what it does under that, and its control on the right.
//
// A setting is a plain object, which is all a page has to write to add one:
//
//   type      "toggle", "choice", "dropdown", "slider" or "text": which control
//   title     its name
//   text      what it does, optional
//   tooltip   extra help shown on info-icon hover, optional
//   icon      an icon name or path, or glyph, a Theme.glyph value; optional
//   get, set  read and write the value, wherever it lives (Settings,
//             DrawerPins, ...). `get` is read in a binding, so whatever it
//             reads keeps the control current.
//
// and, by type:
//
//   choice, dropdown    options: [{ value, label }]; a choice of more than
//             three, or with a long label, is drawn as a dropdown
//   slider    from, to, step, and format(value) for the readout
//   text      placeholder
//
// A new kind of control is one file beside this one, taking `setting`, and
// one line in `controls` below. A toggle row answers to a click anywhere on
// it, the way a list of ticks does.
Item {
    id: root

    required property var setting

    Accessible.role: Accessible.CheckBox
    Accessible.name: root.setting.title
    Accessible.ignored: root.setting.type !== "toggle"
    Accessible.checked: root.setting.type === "toggle" && root.setting.get() === true
    Accessible.onPressAction: if (root.setting.type === "toggle" && root.enabled && root.visible)
        root.setting.set(!root.setting.get())
    Accessible.onToggleAction: if (root.setting.type === "toggle" && root.enabled && root.visible)
        root.setting.set(!root.setting.get())

    readonly property var controls: ({
            toggle: "SettingSwitch.qml",
            choice: "SettingChoice.qml",
            dropdown: "SettingDropdown.qml",
            slider: "SettingSlider.qml",
            text: "SettingField.qml"
        })

    // Up to three short options sit side by side in a capsule; more, or
    // longer, go behind a pop-up button, the way a Mac's settings do.
    function fitsCapsule(options: var): bool {
        return options.length <= 3 && options.every(option => String(option.label).length <= 8);
    }
    readonly property string kind: root.setting.type === "choice" && !root.fitsCapsule(root.setting.options) ? "dropdown" : root.setting.type

    readonly property bool hasMark: !!(root.setting.icon || root.setting.glyph)
    readonly property int lead: root.hasMark ? 32 : Theme.popupInset
    readonly property bool stacked: control.implicitWidth > (root.width - root.lead - 24) / 2

    implicitHeight: Math.max(28, words.implicitHeight + (root.setting.text ? 12 : 8),
        root.stacked ? words.implicitHeight + control.height + 20 : control.height + 12)

    Rectangle {
        anchors.fill: parent
        radius: Theme.selectionRadius
        color: hover.hovered ? Theme.selection : "transparent"
        visible: root.setting.type === "toggle"
    }

    HoverHandler {
        id: hover
    }

    HoverPopup {
        anchorItem: info
        anchorHeight: info.height
        hovered: infoHover.containsMouse && root.visible && root.enabled
        text: root.setting.tooltip ?? ""
        // Settings help sits over other text, so its fill must hide what is behind it.
        onItemChanged: if (item)
            item.chromeItem.color = Qt.binding(() => Theme.solid)
    }

    TapHandler {
        id: rowTap

        enabled: root.setting.type === "toggle"
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.setting.set(!root.setting.get())
    }

    // The thing itself, as the launcher and the bar draw it.
    Item {
        x: Theme.popupInset
        width: 16
        height: 16
        y: words.y + Math.round((title.implicitHeight - 16) / 2)
        visible: root.hasMark

        Image {
            id: icon

            anchors.centerIn: parent
            width: 16
            height: 16
            sourceSize: Qt.size(32, 32)
            source: !root.setting.icon ? "" : String(root.setting.icon).includes("/") ? root.setting.icon : "image://icon/" + root.setting.icon
            visible: status === Image.Ready
        }

        Glyph {
            anchors.centerIn: parent
            visible: !icon.visible
            text: root.setting.glyph ?? Theme.glyph.window
            fontSize: Theme.popupGlyphSize
        }
    }

    Column {
        id: words

        x: root.lead
        y: root.stacked ? 6 : Math.round((root.height - height) / 2)
        width: root.stacked ? root.width - x - Theme.popupInset : control.x - 16 - x
        spacing: 2

        Item {
            width: parent.width
            height: Math.max(title.implicitHeight, info.visible ? info.height : 0)

            PopupText {
                id: title

                width: Math.min(implicitWidth, parent.width - (info.visible ? 22 : 0))
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: root.setting.title
            }

            Item {
                id: info

                x: title.width + 6
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                visible: !!root.setting.tooltip

                Glyph {
                    anchors.centerIn: parent
                    height: parent.height
                    text: "\u{f02fd}" // nf-md-information_outline
                    fontSize: Theme.popupGlyphSize
                    color: Theme.label2
                }

                ClickArea {
                    id: infoHover

                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    hoverEnabled: true
                    hovers: true
                    name: root.setting.title + " help"
                    hint: root.setting.tooltip ?? ""
                }
            }
        }

        PopupText {
            width: parent.width
            visible: !!root.setting.text
            text: root.setting.text ?? ""
            wrapMode: Text.Wrap
            color: Theme.label2
            font.pixelSize: Theme.captionSize
            lineHeight: 1.15
        }
    }

    Loader {
        id: control

        x: root.stacked ? root.lead : root.width - width - Theme.popupInset
        y: root.stacked ? words.y + words.height + 8 : Math.round((root.height - height) / 2)
        width: Math.min(implicitWidth, root.width - root.lead - Theme.popupInset)
        source: root.controls[root.kind] ?? ""
        onLoaded: {
            item.setting = Qt.binding(() => root.setting);
            // A switch stretches its knob while the row is pressed.
            if (root.setting.type === "toggle")
                item.held = Qt.binding(() => rowTap.pressed);
        }
    }
}

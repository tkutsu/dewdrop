import QtQuick
import qs

// One setting in the settings window: what it is on the left, a line or two
// on what it does under that, and its control on the right.
//
// A setting is a plain object, which is all a page has to write to add one:
//
//   type      "toggle", "choice", "slider" or "text": which control
//   title     its name
//   text      what it does, optional
//   icon      an icon name or path, or glyph, a Theme.glyph value; optional
//   get, set  read and write the value, wherever it lives (Settings,
//             DrawerPins, ...). `get` is read in a binding, so whatever it
//             reads keeps the control current.
//
// and, by type:
//
//   choice    options: [{ value, label }]
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
            slider: "SettingSlider.qml",
            text: "SettingField.qml"
        })

    readonly property bool hasMark: !!(root.setting.icon || root.setting.glyph)
    readonly property int lead: root.hasMark ? 32 : 8

    implicitHeight: Math.max(28, words.implicitHeight + (root.setting.text ? 12 : 8))

    Rectangle {
        anchors.fill: parent
        radius: Theme.selectionRadius
        color: hover.hovered ? Theme.selection : "transparent"
        visible: root.setting.type === "toggle"
    }

    HoverHandler {
        id: hover
    }

    TapHandler {
        enabled: root.setting.type === "toggle"
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.setting.set(!root.setting.get())
    }

    // The thing itself, as the launcher and the bar draw it.
    Item {
        x: 8
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
        anchors.verticalCenter: parent.verticalCenter
        width: control.x - 16 - x
        spacing: 2

        PopupText {
            id: title

            width: parent.width
            elide: Text.ElideRight
            text: root.setting.title
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

        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        source: root.controls[root.setting.type] ?? ""
        onLoaded: item.setting = Qt.binding(() => root.setting)
    }
}

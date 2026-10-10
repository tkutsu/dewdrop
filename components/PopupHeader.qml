import QtQuick
import Quickshell
import qs

// The top line of a popup: what it is on the left, and the things that act on
// all of it on the right. The buttons used to be a foot under a rule, below
// however long the list turned out to be; up here they are in the same place
// every time the popup opens. The notification centre set the pattern.
//
// Buttons are the children, laid in a row from the right edge. A framed
// PopupButton supplies the header controls.
//
// A popup that can make another of what it lists (a task, a timer, a mail)
// sets `addable`, and a bare plus closes the line. With nothing else beside
// it the whole header is the press, lit like a row under the pointer; beside
// other controls it is only the plus.
Item {
    id: root

    property string title: ""
    default property alias buttons: row.data
    // The title's inset from the popup's edge, level with the text of the rows
    // under it.
    property int inset: 6
    property bool addable: false

    // A Row lays out only what is visible, so with every other control away
    // it has no width.
    readonly property bool addOnly: root.addable && row.implicitWidth === 0

    signal add

    implicitWidth: root.inset + name.implicitWidth + 12 + row.implicitWidth + (root.addable ? plus.width + row.spacing : 0)
    implicitHeight: 22

    Item {
        id: target

        Accessible.role: Accessible.Button
        Accessible.name: "Add " + root.title.toLowerCase()
        Accessible.onPressAction: if (root.addable && root.enabled && root.visible)
            root.add()

        // The keys (Popup.qml), lit the way the pointer lights it.
        property bool keyed: false
        readonly property var keyPress: () => root.add()
        readonly property bool lit: QsWindow.window?.keyItem ? target.keyed : hover.hovered

        visible: root.addable
        anchors.right: parent.right
        width: root.addOnly ? parent.width : plus.width
        height: parent.height

        Rectangle {
            anchors.fill: parent
            visible: root.addOnly
            radius: Theme.selectionRadius
            color: target.lit ? Theme.selection : "transparent"
        }

        // On the pitch of a row's controls, so it heads their column.
        Item {
            id: plus

            anchors.right: parent.right
            width: 20
            height: parent.height

            Glyph {
                anchors.centerIn: parent
                implicitHeight: parent.height
                text: Theme.glyph.plus
                fontSize: Theme.popupTextSize
                opacity: target.lit ? 1 : 0.6
            }
        }

        HoverHandler {
            id: hover
        }

        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: root.add()
        }
    }

    PopupText {
        id: name

        x: root.inset
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - row.width - (root.addable ? plus.width + row.spacing : 0) - 8
        text: root.title
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    Row {
        id: row

        anchors.right: parent.right
        anchors.rightMargin: root.addable ? plus.width + spacing : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
    }
}

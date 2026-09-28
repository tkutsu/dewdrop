import QtQuick
import qs

// The top line of a popup: what it is on the left, and the things that act on
// all of it on the right. The buttons used to be a foot under a rule, below
// however long the list turned out to be; up here they are in the same place
// every time the popup opens. The notification centre set the pattern.
//
// Buttons are the children, laid in a row from the right edge. A framed
// PopupButton at `buttonHeight` is what goes here.
Item {
    id: root

    property string title: ""
    default property alias buttons: row.data
    // The title's inset from the popup's edge, level with the text of the rows
    // under it.
    property int inset: 6

    readonly property int buttonHeight: 20

    implicitWidth: root.inset + name.implicitWidth + 12 + row.implicitWidth
    implicitHeight: 22

    PopupText {
        id: name

        x: root.inset
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - row.width - 8
        text: root.title
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    Row {
        id: row

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
    }
}

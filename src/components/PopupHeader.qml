import QtQuick
import qs.src.core

// The top line of a popup: what it is on the left, and the things that act on
// all of it on the right. The buttons used to be a foot under a rule, below
// however long the list turned out to be; up here they are in the same place
// every time the popup opens. The notification centre set the pattern.
//
// Buttons are the children, laid in a row from the right edge. A framed
// PopupButton supplies the header controls.
//
// A popup that can make another of what it lists (a task, a timer, a mail)
// sets `addable`: a framed button like the others, first of them, with a
// plus. A popup whose one thing to do is that button's (Updates: upgrade)
// gives it another mark and name. The title stays words, not a target.
Item {
    id: root

    property string title: ""
    default property alias buttons: row.data
    // The title's inset from the popup's edge, level with the text of the rows
    // under it.
    property int inset: Theme.popupInset
    property bool addable: false
    property string addGlyph: Theme.glyph.plus
    property string addLabel: "New"
    property string addName: "Add " + root.title.toLowerCase()
    readonly property alias addButton: action

    signal add

    implicitWidth: root.inset + name.implicitWidth + 12 + row.implicitWidth + (root.addable ? action.implicitWidth + row.spacing : 0)
    implicitHeight: Math.max(20, name.implicitHeight, row.implicitHeight)

    PopupButton {
        id: action

        anchors.right: row.left
        anchors.rightMargin: row.implicitWidth > 0 ? row.spacing : 0
        anchors.verticalCenter: parent.verticalCenter
        visible: root.addable
        framed: true
        label: root.addLabel
        glyph: root.addGlyph
        name: root.addName
        onTapped: root.add()
    }

    PopupText {
        id: name

        x: root.inset
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, (root.addable ? action.x : row.x) - x - 8)
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

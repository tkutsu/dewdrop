import QtQuick
import qs

// A control inside a popup: a glyph, a word, or both, on a target the size of a
// row. Every button under the bar is one of these — a timer's pause, a queue
// row's move-up, "add", "undo", a preset duration — so they all read the same
// way, sit quiet until the pointer is on them, and take a press the same way.
//
// The press is taken on release inside the box. A slipped press that wanders
// off does not count, and a button standing on a row that is itself a button
// takes the press rather than letting the row have it too — "cancel the timer
// and also start it" is the bug that policy exists to prevent.
Item {
    id: root

    property string glyph: ""
    property string label: ""
    // Drawn but not answering. A control with nothing to do right now stays
    // where it is and goes faint, rather than leaving and letting its
    // neighbours slide under a pointer already on its way to them.
    property bool live: true
    // The one that asks twice: armed, it turns the bar's warning colour.
    property bool warn: false
    // Outlined, for the ones that stand on their own in a popup's foot rather
    // than in a run of controls at the end of a row.
    property bool framed: false
    property int glyphSize: Theme.popupTextSize
    property int textSize: Theme.popupTextSize - 1

    readonly property bool hovered: hover.hovered

    signal tapped

    // A run of plain controls is laid out on a fixed pitch so the columns line
    // up down a list; a framed one is as wide as what it says.
    implicitWidth: framed ? content.implicitWidth + 14 : 20
    implicitHeight: 22

    Rectangle {
        anchors.fill: parent
        visible: root.framed
        radius: Theme.selectionRadius
        color: root.hovered ? Theme.selection : "transparent"
        border.width: Theme.pillBorder
        border.color: Theme.stroke
    }

    Row {
        id: content

        anchors.centerIn: parent
        spacing: 3
        opacity: !root.live ? 0.15 : root.hovered ? 1 : (root.framed ? 0.7 : 0.6)

        Glyph {
            visible: root.glyph !== ""
            text: root.glyph
            fontSize: root.glyphSize
            implicitHeight: root.height
            color: root.warn ? Theme.warn : Theme.fg
        }

        PopupText {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.label !== ""
            text: root.label
            font.pixelSize: root.textSize
        }
    }

    HoverHandler {
        id: hover
    }

    TapHandler {
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: if (root.live)
            root.tapped()
    }
}

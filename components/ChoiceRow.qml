import QtQuick
import qs

// A row in a list of things to have one of: an output, a device, a network.
// The tick on the one in use goes in the column where the music queue marks
// the song that is playing and a tray menu its checked item, then the name,
// weighted and lit the way the queue does its current song, then whatever the
// row has to say at its right edge, laid out right to left by whoever uses it.
//
// `busy` is for something under way — a device connecting, a network being
// joined — and puts a spinner at the right edge in place of the rest.
PopupRow {
    id: root

    property string text
    property bool current: false
    property bool busy: false
    name: root.text
    Accessible.selected: root.current

    // The right edge, for status: a battery, a lock, a signal, a forget.
    default property alias trail: tail.data

    // The mark's column, as the music queue's: in six, eighteen wide, eight
    // of air before the name.
    readonly property int lead: 32

    height: 22
    gesturePolicy: TapHandler.ReleaseWithinBounds

    Glyph {
        x: 6 + Math.round((18 - implicitWidth) / 2)
        height: parent.height
        visible: root.current
        text: Theme.glyph.check
        // 12, not the caption's 11: the symbol font only lands on the pixel
        // grid at even sizes.
        fontSize: Theme.popupTextSize
    }

    PopupText {
        x: root.lead
        anchors.verticalCenter: parent.verticalCenter
        width: (root.busy ? spinner.x - 8 : tail.width > 0 ? tail.x - 8 : root.width - 6) - x
        elide: Text.ElideRight
        text: root.text
        font.pixelSize: Theme.captionSize
        font.weight: root.current ? Font.DemiBold : Font.Normal
        opacity: root.current ? 1 : 0.8
    }

    Spinner {
        id: spinner

        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        visible: root.busy
    }

    Row {
        id: tail

        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        spacing: 6
        visible: !root.busy
    }
}

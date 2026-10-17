import QtQuick
import qs

// A count or attention dot on an icon's top right corner. Counts use the workspace
// mark's glass, made solid (Theme.badgeBg) over its own pill, with a white number. It grows into a pill rather than staying round, because "20" and "99"
// have to fit the same badge a "2" does.
//
// The disc is opaque unless its owner says otherwise. It spends half its area
// over the icon's own white strokes, and anything it let through came up under
// the digit and ate into its contrast.
//
// The count rolls to its next value the way the timer's figures do
// (RollingText): up when it grows, down when it shrinks.
Item {
    id: root

    property alias text: label.text
    property bool dot: false
    property int dotSize: Theme.badgeDotSize
    property color fill: Theme.badgeBg(root)
    // A single digit fills the disc. Past that the badge becomes a capsule,
    // and a capsule wants more air at its ends than a disc does round its
    // middle: at the disc's 3px a "20" sat with its digits touching the
    // rounded ends and read as cramped.
    readonly property int pad: label.text.length > 1 ? 4 : 3

    // What the count last was, for which way the next one rolls.
    property real was: 0
    onTextChanged: {
        const now = Number(text);
        label.countsDown = now < was;
        was = now;
    }

    implicitWidth: dot ? dotSize : Math.max(Theme.badgeSize, Math.ceil(label.implicitWidth) + pad * 2)
    implicitHeight: dot ? dotSize : Theme.badgeSize

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.dot ? Qt.rgba(1, 1, 1, 0.7) : root.fill

        Rim {
            visible: !root.dot
            anchors.fill: parent
            radius: parent.radius
            topColor: Theme.markRimTop
        }
    }

    RollingText {
        id: label
        visible: !root.dot
        columns: 3
        anchors.horizontalCenter: parent.horizontalCenter
        // An eight-row figure in a thirteen-row disc, left where it falls:
        // two rows over it and three under, which is the high-of-centre a
        // figure wants. At a twelve-row disc it needed a row's lift (y: -1).
        height: parent.height
        color: Theme.badgeFg
        fontSize: Theme.badgeTextSize
        weight: Font.Bold
    }
}

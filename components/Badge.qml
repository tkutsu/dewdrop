import QtQuick
import qs

// The count that sits on an icon's top right corner: a dark disc with a white
// number. It grows into a pill rather than staying round, because "20" and "99"
// have to fit the same badge a "2" does.
//
// The disc is opaque unless its owner says otherwise. It spends half its area
// over the icon's own white strokes, and anything it let through came up under
// the digit and ate into its contrast.
Item {
    id: root

    property alias text: label.text
    property color fill: Theme.badgeBg
    // A single digit fills the disc. Past that the badge becomes a capsule,
    // and a capsule wants more air at its ends than a disc does round its
    // middle: at the disc's 3px a "20" sat with its digits touching the
    // rounded ends and read as cramped.
    readonly property int pad: label.text.length > 1 ? 4 : 3

    implicitWidth: Math.max(Theme.badgeSize, Math.ceil(label.implicitWidth) + pad * 2)
    implicitHeight: Theme.badgeSize

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.fill
    }

    Text {
        id: label
        anchors.centerIn: parent
        color: Theme.badgeFg
        font.family: Theme.bodyFont
        font.features: Theme.figures
        font.pixelSize: Theme.badgeTextSize
        font.bold: true
    }
}

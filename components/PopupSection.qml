import QtQuick
import qs

// Where a popup's next part begins: a hairline, then its name, the way the
// Mac's Sound menu heads Output and Input. Smaller and greyer than the
// popup's own title, so it reads as a part of the popup rather than a second
// one. Controls that act on the section alone are its children, laid from the
// right edge as PopupHeader lays its own: the wallpaper's Monochrome switch.
//
// The air round the hairline is the section's own, so the step from one part
// to the next is the same in every popup. The first part under a header
// (Network's Wi-Fi, Bluetooth's Devices) drops the hairline: the header
// already closes off what is above it.
Item {
    id: root

    property string title: ""
    property bool ruled: true
    default property alias controls: row.data

    implicitWidth: Theme.popupInset + name.implicitWidth + 12 + row.implicitWidth
    implicitHeight: heading.y + heading.height

    PopupSeparator {
        id: rule
        visible: root.ruled
        y: Theme.popupSectionGap
        width: root.width
    }

    Item {
        id: heading

        y: root.ruled ? rule.y + rule.height + Theme.popupSectionGap / 2 : 0
        width: root.width
        height: Math.max(20, name.implicitHeight, row.implicitHeight)

        PopupText {
            id: name

            x: Theme.popupInset
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, row.x - x - 8)
            text: root.title
            color: Theme.label2
            font.pixelSize: Theme.captionSize
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            Accessible.role: Accessible.Heading
            Accessible.name: root.title
        }

        Row {
            id: row

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
        }
    }
}

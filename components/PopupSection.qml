import QtQuick
import qs

// Where a popup's next part begins: a hairline, then its name, the way the
// Mac's Sound menu heads Output and Input. Smaller and greyer than the
// popup's own title, so it reads as a part of the popup rather than a second
// one. Controls that act on the section alone are its children, laid from the
// right edge as PopupHeader lays its own: the night mode schedule's switch,
// the wallpaper's drift.
Item {
    id: root

    property string title: ""
    default property alias controls: row.data

    implicitWidth: Theme.popupInset + name.implicitWidth + 12 + row.implicitWidth
    implicitHeight: heading.y + heading.height

    PopupSeparator {
        id: rule
        width: root.width
    }

    Item {
        id: heading

        y: rule.height + Theme.popupSpacing
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

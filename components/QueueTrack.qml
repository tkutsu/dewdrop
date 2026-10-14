import QtQuick
import qs
import qs.services

// The same track readout stays under a queue row and its lifted drag preview.
Item {
    id: root
    property var song: null
    property int number: 0
    property bool current: false
    property bool showDuration: true
    required property real tailWidth

    PopupText {
        id: ordinal
        x: Theme.popupInset
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        horizontalAlignment: Text.AlignRight
        text: root.current ? Mpd.stateIcon : String(root.number)
        font.family: root.current ? Theme.glyphFont : Theme.bodyFont
        font.pixelSize: Theme.footnoteSize
        opacity: root.current ? 1 : 0.4
    }
    Item {
        id: line
        x: ordinal.x + ordinal.width + 8
        width: parent.width - x - root.tailWidth - 8
        height: parent.height
        PopupText {
            id: title
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.song?.artist ? line.width * 0.62 : line.width)
            text: root.song?.title ?? ""
            font.pixelSize: Theme.captionSize
            font.weight: root.current ? Font.DemiBold : Font.Normal
            opacity: root.current ? 1 : 0.8
            elide: Text.ElideRight
        }
        PopupText {
            anchors.left: title.right
            anchors.leftMargin: 6
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.song?.artist ?? ""
            font.pixelSize: Theme.captionSize
            opacity: 0.45
            elide: Text.ElideRight
        }
    }
    PopupText {
        anchors.right: parent.right
        anchors.rightMargin: Theme.popupInset
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showDuration
        text: Mpd.clock(root.song?.duration ?? 0)
        font.pixelSize: Theme.footnoteSize
        opacity: 0.4
    }
}

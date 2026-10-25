import QtQuick
import qs

// A compact readout with an upright label and a track that fills from below.
Column {
    id: root

    property string name
    property string icon
    property int level
    property bool readoutOnTop: false

    width: 34
    spacing: Theme.popupSpacing

    PopupText {
        visible: root.readoutOnTop
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.level + "%"
    }

    Glyph {
        visible: root.icon !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        height: Theme.popupTextSize + 4
        text: root.icon
        fontSize: Theme.popupTextSize
    }

    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 14
        height: 140

        Slider {
            anchors.centerIn: parent
            width: parent.height
            height: parent.width
            rotation: -90
            name: root.name
            value: root.level / 100
        }
    }

    PopupText {
        visible: !root.readoutOnTop
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.level + "%"
    }
}

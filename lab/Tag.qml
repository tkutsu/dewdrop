import QtQuick
import qs

// A prototype's name, legible on any part of the wallpaper.
Rectangle {
    property alias text: label.text

    width: label.implicitWidth + 20
    height: 24
    radius: height / 2
    color: Qt.rgba(0, 0, 0, 0.6)

    Text {
        id: label

        anchors.centerIn: parent
        color: Theme.label
        font.family: Settings.font
        font.pixelSize: 12
    }
}

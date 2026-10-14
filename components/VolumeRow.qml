import QtQuick
import qs

// A mute control, normalized volume slider and percentage shared by audio and music.
Row {
    id: volumeRow

    property string icon
    property int volume
    property string name: "Output"
    property bool iconBeforeReadout: false
    property alias sliderWidth: slider.width
    property alias readoutWidth: readoutSpace.width
    property alias iconWidth: speaker.width
    property alias iconFontSize: glyph.fontSize
    property alias wheelStep: slider.wheelStep
    property alias wheelSnap: slider.wheelSnap
    property alias readoutOpacity: readout.opacity
    property alias readoutFontSize: readout.font.pixelSize
    signal moved(real value)
    signal iconTapped

    // On the lists' grid (ChoiceRow): the speaker in the tick's column,
    // the track starting where the names do.
    leftPadding: Theme.popupInset
    rightPadding: Theme.popupInset
    spacing: Theme.popupInset * 2

    Item {
        id: leadingSpeaker
        anchors.verticalCenter: parent.verticalCenter
        visible: !volumeRow.iconBeforeReadout
        width: speaker.width
        height: speaker.height
    }

    // A fixed box, with the speaker against its left edge: the struck-out
    // speaker is not the width of the others, and a glyph sized to its
    // own ink shoved the slider along whenever it came or went. Two
    // pixels past the font size holds either.
    Item {
        id: speaker
        parent: volumeRow.iconBeforeReadout ? readoutSpace : leadingSpeaker

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: volumeRow.iconBeforeReadout ? readout.left : undefined
        anchors.rightMargin: volumeRow.spacing
        width: Theme.popupTextSize + 2
        height: Theme.popupTextSize + 4

        Glyph {
            id: glyph
            anchors.right: volumeRow.iconBeforeReadout ? parent.right : undefined
            height: parent.height
            text: volumeRow.icon
            fontSize: Theme.popupTextSize
        }

        Accessible.role: Accessible.Button
        Accessible.name: "Toggle " + volumeRow.name.toLowerCase() + " mute"
        Accessible.onPressAction: if (enabled && visible)
            volumeRow.iconTapped()
        readonly property var keyPress: () => volumeRow.iconTapped()

        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: volumeRow.iconTapped()
        }
    }

    Slider {
        id: slider
        anchors.verticalCenter: parent.verticalCenter
        name: volumeRow.name + " volume"
        value: volumeRow.volume / 100
        // PipeWire takes the change directly — no pamixer round trip,
        // so the track keeps up with the drag.
        onMoved: value => volumeRow.moved(value)
    }

    Item {
        id: readoutSpace
        anchors.verticalCenter: parent.verticalCenter
        width: 34
        height: Math.max(readout.implicitHeight, volumeRow.iconBeforeReadout ? speaker.height : 0)

        PopupText {
            id: readout
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: volumeRow.iconBeforeReadout ? implicitWidth : parent.width
            horizontalAlignment: Text.AlignRight
            text: volumeRow.volume + "%"
        }
    }
}

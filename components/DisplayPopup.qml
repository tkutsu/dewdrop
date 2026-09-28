import QtQuick
import qs
import qs.services

// The night mode module's popup, laid out like Control Center's display
// module: the brightness on a track the pointer can grab, and night mode as
// a toggle beside the title, drawn the way the notification centre draws do
// not disturb.
Popup {
    id: root

    spacing: 6

    PopupHeader {
        width: row.width
        inset: 0
        title: "Display"

        PopupButton {
            framed: true
            lit: NightMode.on
            glyph: Theme.glyph.nightOn
            label: "night mode"
            onTapped: NightMode.toggle()
        }
    }

    // The sun, the track and the figure, on the audio popup's grid.
    Row {
        id: row

        leftPadding: 8
        spacing: 10

        Glyph {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.popupTextSize + 2
            height: Theme.popupTextSize + 4
            tightWidth: false
            text: Theme.glyph.nightOff
            fontSize: Theme.popupTextSize
        }

        Slider {
            anchors.verticalCenter: parent.verticalCenter
            value: NightMode.brightness / 100
            onMoved: value => NightMode.setBrightness(value * 100)
        }

        PopupText {
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            horizontalAlignment: Text.AlignRight
            text: NightMode.brightness + "%"
        }
    }
}

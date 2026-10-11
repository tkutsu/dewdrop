import QtQuick
import qs
import qs.components

// The accent colour row as the settings window draws it, cycling through the
// accents on a local setting (settings.json is left alone), with a slider and
// a switch-shaped track filled in the one chosen.
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    property string chosen: "white"
    readonly property var keys: Object.keys(Theme.accents)
    readonly property color tone: Theme.accents[chosen]

    Timer {
        running: true
        repeat: true
        interval: 700
        onTriggered: scene.chosen = scene.keys[(scene.keys.indexOf(scene.chosen) + 1) % scene.keys.length]
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 12
        radius: Theme.popupRadius
        color: Theme.popupBg

        Column {
            x: 18
            y: 16
            spacing: 14

            SettingChoice {
                setting: ({ title: "Accent colour", options: scene.keys.map(k => ({ value: k, label: k, swatch: Theme.accents[k] })), get: () => scene.chosen, set: v => scene.chosen = v })
            }

            Row {
                spacing: 16

                Slider {
                    width: 160
                    value: 0.6
                    fill: scene.tone
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    width: 28
                    height: 16
                    radius: 8
                    color: scene.tone
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        x: 14
                        y: 2
                        width: 12
                        height: 12
                        radius: 6
                        color: scene.chosen === "white" ? "black" : "white"
                    }
                }

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: scene.tone

                    PopupText {
                        anchors.centerIn: parent
                        text: "11"
                        color: scene.chosen === "white" ? "black" : "white"
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }
}

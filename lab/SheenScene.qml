import QtQuick
import qs
import qs.components

// Resting border light at actual bar height, with pointer and click light disabled.
Item {
    id: scene
    required property Item backdrop
    required property Item blurred

    Repeater {
        model: [
            {title: "S4  Visible edge", detail: "Clear rim, close to the edge", sheen: Qt.vector4d(-0.60, -0.80, 0.15, 0.28), bloom: Qt.vector4d(0.045, 2.5, 0.012, 1.8)},
            {title: "S5  Diffuse rim", detail: "Broader light inside the border", sheen: Qt.vector4d(-0.60, -0.80, 0.08, 0.34), bloom: Qt.vector4d(0.10, 4.5, 0.015, 2.0)},
            {title: "S6  Soft halo", detail: "Light inside and around the edge", sheen: Qt.vector4d(-0.60, -0.80, 0.12, 0.30), bloom: Qt.vector4d(0.07, 3.5, 0.055, 2.5)}
        ]
        delegate: Item {
            id: col
            required property var modelData
            required property int index
            x: index * 360; width: 360; height: scene.height
            Tag { x: 24; y: 18; text: col.modelData.title }
            Tag { x: 24; y: 45; text: col.modelData.detail }
            Repeater {
                model: [0, 1, 2]
                delegate: Item {
                    id: sample
                    required property int modelData
                    x: 18; y: 86 + modelData * 72; width: 324; height: 52
                    Rectangle {
                        anchors.fill: parent; radius: 4
                        color: "#121b20"; visible: sample.modelData === 1
                    }
                    Liquid {
                        anchors.fill: parent
                        backdrop: sample.modelData === 1 ? null : scene.backdrop
                        fill: sample.modelData === 1 ? Qt.vector4d(0.06, 0.085, 0.10, 1)
                            : Qt.vector4d(Theme.barBg.r, Theme.barBg.g, Theme.barBg.b, Theme.barBg.a)
                        box0: Qt.vector4d(6, 11, 312, 30)
                        rimFrom: 11; rimTo: 41
                        sheen: col.modelData.sheen; sheenBloom: col.modelData.bloom
                        takesPress: false; hover: Qt.vector4d(0,0,1,0)
                        press: Qt.vector4d(0,0,1,0); deform: Qt.vector4d(0,0,1,0)
                    }
                    Text {
                        x: 6; y: 11; width: 312; height: 30
                        text: sample.modelData === 2 ? "Clock       Timer  05:00" : "Sun 11 Oct        15:20"
                        color: Theme.fg; font.family: Settings.font; font.pixelSize: Theme.textSize
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                }
            }
            Tag { x: 24; y: 312; text: "Static light, no hover or click" }
        }
    }
}

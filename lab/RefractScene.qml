import QtQuick
import qs
import qs.components

// The pills' glass against the light/dark reel: a page like the reel's
// (a red masthead, a white page of dark type, a dark photograph) scrolls up
// under three pills, the real Liquid glass each time:
//
//   R0  the glass as it is
//   R1  the bend kept to a narrow band at the rim, and more blur in the
//       flat middle, which is how the reel's glass bends
//   R2  R1, and it turns light over light ground, with dark ink, and dark
//       over dark ground, as the reel's does
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    // The page, scrolled.
    property real scroll: 0
    SequentialAnimation on scroll {
        loops: Animation.Infinite
        PauseAnimation { duration: 500 }
        NumberAnimation { to: 640; duration: 5200; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 500 }
        NumberAnimation { to: 0; duration: 2400; easing.type: Easing.InOutSine }
    }

    readonly property real pillY: 70
    // How light the page is under the pills, from the section there, eased
    // so the glass turns rather than flips. Known here because the lab drew
    // the page; the bar would read it off the wallpaper (Pill.surface).
    readonly property var sections: [
        { h: 150, luma: 0.2 }, // masthead red
        { h: 300, luma: 0.95 }, // page
        { h: 340, luma: 0.08 }, // photograph
        { h: 200, luma: 0.95 }
    ]
    readonly property real target: {
        let y = scene.scroll + scene.pillY + Theme.barHeight / 2, top = 0;
        for (const s of sections) {
            if (y < top + s.h)
                return s.luma;
            top += s.h;
        }
        return 0.95;
    }
    property real luma: target
    FrameAnimation {
        running: true
        onTriggered: scene.luma += (scene.target - scene.luma) * (1 - Math.exp(-frameTime / 0.12))
    }
    readonly property real light: Math.min(1, Math.max(0, (luma - 0.4) / 0.3))

    Item {
        id: page

        anchors.fill: parent
        clip: true

        Column {
            y: -scene.scroll
            width: parent.width

            Rectangle {
                width: parent.width
                height: 150
                color: "#d21f3c"
                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 20
                    text: "FOOD & WINE"
                    color: "white"
                    font.pixelSize: 40
                    font.weight: Font.Black
                    font.family: Settings.font
                }
            }
            Rectangle {
                width: parent.width
                height: 300
                color: "white"
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "SHORT CUTS  SHORT CUTS"
                        color: "#1a2a4a"
                        font.pixelSize: 64
                        font.family: "serif"
                        font.weight: Font.Bold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Short pastas are a marvel of modern engineering and perfect for easy weeknight dinners."
                        color: "#222"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        font.family: Settings.font
                    }
                }
            }
            Rectangle {
                width: parent.width
                height: 340
                color: "#0b0b0b"
                clip: true
                Image {
                    anchors.fill: parent
                    source: "file:///home/kutsui/_media/wallpapers/nature/akshaya-jayaprakash-XgY0NxAWlL0-unsplash.jpg"
                    sourceSize.width: 1600
                    fillMode: Image.PreserveAspectCrop
                    opacity: 0.4
                }
            }
            Rectangle {
                width: parent.width
                height: 200
                color: "white"
                Text {
                    x: 60
                    y: 30
                    width: parent.width - 120
                    wrapMode: Text.WordWrap
                    text: "STROLL DOWN THE PASTA AISLE at your local supermarket and it presents you with a panoply of forms, textures, and names: tubular penne, corkscrew-shaped cavatappi, ruffled radiatori."
                    color: "#1a1a1a"
                    font.pixelSize: 20
                    font.family: "serif"
                }
            }
        }
    }

    ShaderEffectSource {
        id: pageTex

        property real glassWeight: 1
        anchors.fill: parent
        sourceItem: page
        live: true
        visible: false
    }

    Row {
        Variant { title: "R0 · today" }
        Variant { title: "R1 · narrow rim, more blur"; bendDepth: 7; soften: 3.5; bend: 12 }
        Variant { title: "R2 · R1, light and dark"; bendDepth: 7; soften: 3.5; bend: 12; adapts: true }
    }

    component Variant: Item {
        id: v

        required property string title
        property real bend: Theme.glassBend
        property real bendDepth: Theme.glassBendDepth
        property real soften: Theme.glassSoften
        property bool adapts: false
        readonly property real light: adapts ? scene.light : 0

        width: scene.width / 3
        height: scene.height

        Item {
            x: (parent.width - 220) / 2
            y: scene.pillY - Theme.barInset
            width: 220
            height: Theme.barHeight + 2 * Theme.barInset

            Liquid {
                anchors.fill: parent
                backdrop: pageTex
                box0: Qt.vector4d(0, Theme.barInset, width, Theme.barHeight)
                bend: v.bend
                bendDepth: v.bendDepth
                soften: v.soften
                // Light: a white frost thick enough for dark ink to read on;
                // dark: the bar's own tint.
                fill: Qt.vector4d(Theme.barBg.r + (0.97 - Theme.barBg.r) * v.light, Theme.barBg.g + (0.97 - Theme.barBg.g) * v.light, Theme.barBg.b + (0.97 - Theme.barBg.b) * v.light, Theme.barBg.a)
                tint: Theme.glassTint + (0.72 - Theme.glassTint) * v.light
                rimTop: Qt.vector4d(1, 1, 1, Theme.pillRimTop.a + 0.25 * v.light)
            }

            Row {
                anchors.centerIn: parent
                spacing: 28
                Repeater {
                    model: [Theme.glyph.mediaPrev, Theme.glyph.playing, Theme.glyph.mediaNext, Theme.glyph.settings]
                    Glyph {
                        required property string modelData
                        text: modelData
                        color: Qt.rgba(1 - v.light, 1 - v.light, 1 - v.light, 0.85)
                    }
                }
            }
        }

        Tag {
            x: (parent.width - width) / 2
            y: scene.height - 34
            text: v.title
        }
    }
}

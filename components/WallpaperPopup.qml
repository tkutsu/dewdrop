import QtQuick
import qs
import qs.services

// The wallpaper tooltip used to say "8/11". This shows the eleven, and the
// colours that are not among them.
Popup {
    id: root

    readonly property int columns: Math.min(4, Math.max(1, Wallpaper.files.length))
    readonly property real cellWidth: 104
    readonly property real cellHeight: 58
    readonly property real gridWidth: columns * cellWidth + (columns - 1) * 4
    readonly property real bodyWidth: Math.max(320, gridWidth)

    // Everything in a channel row that is not the track, so the three tracks
    // can take whatever the thumbnails above them leave over.
    readonly property real swatchWidth: 56
    readonly property real labelWidth: 12
    readonly property real readoutWidth: 30
    readonly property real rowSpacing: 6
    readonly property real sliderWidth: bodyWidth - swatchWidth - 8 - labelWidth - readoutWidth - rowSpacing * 2

    spacing: 8

    // Hue 0..360, saturation and value 0..100. HSV rather than RGB because the
    // three questions it asks — which colour, how strong, how bright — are the
    // ones being answered, and each has a track that can be painted with its
    // own answer. Red is the opening position: at value 0 every track is black
    // and at saturation 0 every track is grey, so a neutral default would be
    // three sliders that show nothing until one is moved.
    property var hsv: [0, 100, 100]
    readonly property string hex: root.toHex(root.hsv)

    // Reading the HSV back out of a hex means letting the colour type do the
    // conversion, which needs somewhere typed `color` to put it.
    property color parsed: "#000000"

    function toHex(c) {
        // 360 and 0 are the same hue; the modulo is what keeps the far end of
        // the track from falling off the end of the range Qt.hsva accepts.
        const q = Qt.hsva((c[0] % 360) / 360, c[1] / 100, c[2] / 100, 1);
        // No padStart: this runs in whatever JS engine the Quickshell build
        // carries, and a two-character slice is the same length of code.
        return "#" + [q.r, q.g, q.b].map(v => ("0" + Math.round(v * 255).toString(16)).slice(-2)).join("");
    }

    function fromHex(s) {
        root.parsed = s;
        // Whole numbers on the way in as on the way out — the readout has no
        // room for a decimal and a hex has no room for the difference.
        // hsvHue is -1 on a grey, which is a hue no track has.
        return [Math.round(Math.max(0, root.parsed.hsvHue) * 360), Math.round(root.parsed.hsvSaturation * 100), Math.round(root.parsed.hsvValue * 100)];
    }

    // Reopening on a colour should find the sliders where they were left, which
    // the wallpaper itself already records. Only until one is moved, though:
    // re-reading our own writes would round-trip a grey back through a hue it
    // does not have, and walk the markers away under the pointer.
    property bool adopted: false

    function adopt() {
        // The colour on screen if there is one, else the last one there was:
        // picking an image should not cost you the colour you mixed, and the
        // swatch is where you go to get it back.
        const hex = Wallpaper.color || Wallpaper.lastColor;
        if (root.adopted || !hex)
            return;
        root.adopted = true;
        root.hsv = root.fromHex(hex);
    }

    function setChannel(i, v) {
        root.adopted = true;
        // A copy rather than hsv[i] = v: mutating in place leaves the property
        // pointing at the same array, so nothing bound to it re-evaluates.
        const next = root.hsv.slice();
        next[i] = v;
        root.hsv = next;
        Wallpaper.setColor(root.toHex(next));
    }

    // Opening the grid is the one moment the list is looked at rather than
    // stepped through, so it is worth a fresh read of the folder.
    Component.onCompleted: {
        Wallpaper.rescan();
        root.adopt();
    }

    // On a cold start the saved colour arrives with the state file, which can
    // land after this popup has been built.
    Connections {
        target: Wallpaper

        function onColorChanged() {
            root.adopt();
        }

        function onLastColorChanged() {
            root.adopt();
        }
    }

    // The three tracks. Each paints the outcome of moving it from where the
    // other two are sitting, so the hue strip is the colours that would
    // actually land on screen rather than a stock rainbow.
    QtObject {
        id: tracks

        readonly property real h: (root.hsv[0] % 360) / 360
        readonly property real s: root.hsv[1] / 100
        readonly property real v: root.hsv[2] / 100

        property Gradient hue: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0 / 6
                color: Qt.hsva(0 / 6, tracks.s, tracks.v, 1)
            }
            GradientStop {
                position: 1 / 6
                color: Qt.hsva(1 / 6, tracks.s, tracks.v, 1)
            }
            GradientStop {
                position: 2 / 6
                color: Qt.hsva(2 / 6, tracks.s, tracks.v, 1)
            }
            GradientStop {
                position: 3 / 6
                color: Qt.hsva(3 / 6, tracks.s, tracks.v, 1)
            }
            GradientStop {
                position: 4 / 6
                color: Qt.hsva(4 / 6, tracks.s, tracks.v, 1)
            }
            GradientStop {
                position: 5 / 6
                color: Qt.hsva(5 / 6, tracks.s, tracks.v, 1)
            }
            // Hue 1 is out of the range Qt.hsva takes; the wrap back to red is
            // hue 0 again.
            GradientStop {
                position: 6 / 6
                color: Qt.hsva(0, tracks.s, tracks.v, 1)
            }
        }

        property Gradient sat: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: Qt.hsva(tracks.h, 0, tracks.v, 1)
            }
            GradientStop {
                position: 1
                color: Qt.hsva(tracks.h, 1, tracks.v, 1)
            }
        }

        property Gradient val: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: Qt.hsva(tracks.h, tracks.s, 0, 1)
            }
            GradientStop {
                position: 1
                color: Qt.hsva(tracks.h, tracks.s, 1, 1)
            }
        }
    }

    PopupHeader {
        width: root.bodyWidth
        inset: 0
        title: "Wallpaper"
    }

    PopupText {
        visible: Wallpaper.files.length === 0
        text: Wallpaper.tooltip
    }

    Grid {
        x: (root.bodyWidth - width) / 2
        columns: root.columns
        spacing: 4

        Repeater {
            model: Wallpaper.files

            delegate: Item {
                id: cell

                required property string modelData
                required property int index

                readonly property bool current: cell.modelData === Wallpaper.current

                width: root.cellWidth
                height: root.cellHeight

                Image {
                    anchors.fill: parent
                    // The kept thumbnail once there is one (Wallpaper.thumbs).
                    source: "file://" + Wallpaper.thumbOf(cell.modelData)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    // Decoded at cell size: the thumbnail is 512 wide, and
                    // until it exists this is all that stands between a cell
                    // and a full 4K wallpaper in memory.
                    sourceSize.width: root.cellWidth * 2
                    opacity: cell.current || hover.hovered ? 1 : 0.6
                }

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 1
                    border.color: cell.current ? Theme.fg : (hover.hovered ? Theme.outlineHover : "transparent")
                }

                HoverHandler {
                    id: hover
                }

                TapHandler {
                    onTapped: Wallpaper.show(cell.index)
                }
            }
        }
    }

    Rectangle {
        width: root.bodyWidth
        height: 1
        color: Theme.stroke
    }

    PopupHeader {
        width: root.bodyWidth
        inset: 0
        title: "Monochrome"

        // Only a flat colour drifts, so the toggle goes quiet while an image
        // is up, but stays: it is still the setting the next colour gets.
        PopupButton {
            opacity: Wallpaper.color ? 1 : 0.5
            framed: true
            lit: Wallpaper.drift
            glyph: Wallpaper.drift ? Theme.glyph.check : ""
            label: "drift"
            onTapped: Wallpaper.setDrift(!Wallpaper.drift)
        }
    }

    // A flat colour, for the days when none of the eleven are it. Dragging
    // applies straight away — a slider that needed confirming afterwards would
    // be a worse colour picker than the folder it sits under.
    Row {
        spacing: 8

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Rectangle {
                width: root.swatchWidth
                height: 42
                color: root.hex
                border.width: 1
                // Lit the same way a thumbnail is, and for the same reason:
                // this is what is on screen right now.
                border.color: Wallpaper.color === root.hex ? Theme.fg : (swatchHover.hovered ? Theme.outlineHover : Theme.outline)

                HoverHandler {
                    id: swatchHover
                }

                // The twelfth thumbnail, in effect: click it to put the colour
                // back after an image has been on screen. Moving a slider is
                // the other way to it, and a worse one — it changes the colour
                // you were trying to return to.
                TapHandler {
                    onTapped: Wallpaper.setColor(root.hex)
                }
            }

            PopupText {
                width: root.swatchWidth
                horizontalAlignment: Text.AlignHCenter
                text: root.hex
                font.pixelSize: Theme.captionSize
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Repeater {
                // The gradients ride along in the model because they are the
                // one thing that genuinely differs per channel.
                model: [
                    {
                        name: "H",
                        max: 360,
                        track: tracks.hue
                    },
                    {
                        name: "S",
                        max: 100,
                        track: tracks.sat
                    },
                    {
                        name: "V",
                        max: 100,
                        track: tracks.val
                    }
                ]

                delegate: Row {
                    id: channel

                    required property var modelData
                    required property int index

                    spacing: root.rowSpacing

                    PopupText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.labelWidth
                        text: channel.modelData.name
                    }

                    Slider {
                        anchors.verticalCenter: parent.verticalCenter
                        // Sized off the grid so the block of tracks ends where
                        // the row of thumbnails above it does.
                        width: root.sliderWidth
                        height: 14
                        trackGradient: channel.modelData.track
                        value: root.hsv[channel.index] / channel.modelData.max
                        wheelStep: 0.05
                        onMoved: v => root.setChannel(channel.index, Math.round(v * channel.modelData.max))
                    }

                    PopupText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.readoutWidth
                        horizontalAlignment: Text.AlignRight
                        text: root.hsv[channel.index]
                    }
                }
            }
        }
    }
}

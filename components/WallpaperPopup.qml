import QtQuick
import Quickshell
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
    // Past this many rows the thumbnails scroll rather than stretch the popup.
    readonly property int visibleRows: 3
    readonly property real bodyWidth: Math.max(320, gridWidth)
    readonly property real screenAspect: root.screen ? root.screen.height / root.screen.width : 9 / 16

    // Everything in a channel row that is not the track, so the three tracks
    // can take whatever the thumbnails above them leave over.
    readonly property real swatchWidth: 56
    readonly property real labelWidth: 12
    readonly property real readoutWidth: 30
    readonly property real rowSpacing: 6
    readonly property real sliderWidth: bodyWidth - swatchWidth - 8 - labelWidth - readoutWidth - rowSpacing * 2

    spacing: 8
    // Room for the framing up front, so turning parallax on opens it inside a
    // window that keeps its size (see Popup.reserveHeight).
    reserveHeight: root.chromeHeight - framing.height + framing.fullHeight

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

    // The header, and under it while parallax is on, the framing. One block
    // so the framing's gap opens with it instead of jumping in at the start.
    Column {
        PopupHeader {
            width: root.bodyWidth
            inset: 0
            title: "Wallpaper"

            PopupButton {
                framed: true
                lit: Wallpaper.parallax
                glyph: Wallpaper.parallax ? Theme.glyph.check : ""
                label: "parallax"
                onTapped: Wallpaper.setParallax(!Wallpaper.parallax)
            }
        }

        Framing {
            id: framing
        }
    }

    PopupText {
        visible: Wallpaper.files.length === 0
        text: Wallpaper.tooltip
    }

    GridView {
        id: grid

        // In the accessibility tree as a list to scroll, half a view a step.

        Accessible.role: Accessible.List

        Accessible.name: "Wallpapers"

        Accessible.onScrollUpAction: contentY = Math.max(originY, contentY - height / 2)

        Accessible.onScrollDownAction: contentY = Math.min(originY + Math.max(0, contentHeight - height), contentY + height / 2)

        readonly property int rows: Math.ceil(count / root.columns)

        x: (root.bodyWidth - root.gridWidth) / 2
        // Cells carry the gap on their right and bottom; the last ones fall
        // outside the view.
        width: root.gridWidth + 4
        height: Math.max(0, Math.min(rows, root.visibleRows) * cellHeight - 4)
        cellWidth: root.cellWidth + 4
        cellHeight: root.cellHeight + 4
        clip: true
        model: Wallpaper.files
        // Scrolls only when there is more than fits, so the wheel otherwise
        // falls through to whatever is underneath.
        interactive: rows > root.visibleRows
        // Whole rows, as the music queue does, and no momentum past the ends.
        boundsBehavior: Flickable.StopAtBounds
        snapMode: GridView.SnapToRow

        // Open where the wallpaper on screen is, once there are cells to find.
        Component.onCompleted: Qt.callLater(() => {
            const index = Wallpaper.files.indexOf(Wallpaper.current);
            if (index >= 0)
                grid.positionViewAtIndex(index, GridView.Contain);
        })

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
                sourceSize.width: Math.ceil(root.cellWidth * root.devicePixelRatio)
                opacity: cell.current || cell.lit ? 1 : 0.6
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: cell.current ? Theme.fg : (cell.lit ? Theme.outlineHover : "transparent")
            }

            HoverHandler {
                id: hover
            }

            Accessible.role: Accessible.Button
            Accessible.name: "Wallpaper " + cell.modelData.split("/").pop()
            Accessible.onPressAction: if (enabled && visible)
                Wallpaper.show(cell.index)

            // The keys (Popup.qml) light a thumbnail as the pointer does.
            property bool keyed: false
            readonly property var keyPress: () => Wallpaper.show(cell.index)
            readonly property bool lit: QsWindow.window?.keyItem ? cell.keyed : hover.hovered

            TapHandler {
                onTapped: Wallpaper.show(cell.index)
            }
        }
    }

    // Where the parallax crop sits: the picture as the zoom frames it, with a
    // frame round the part on screen. Pressing or dragging puts the frame's
    // height where the pointer is; across is the workspace's to set. It takes
    // no wheel, which in this popup only ever scrolls the thumbnails.
    component Framing: Item {
        id: framing

        readonly property bool shown: Wallpaper.parallax && Wallpaper.current !== ""
        readonly property real previewHeight: 144
        readonly property real fullHeight: framing.previewHeight + root.spacing
        readonly property real zoom: Settings.wallpaperParallaxZoom
        readonly property real across: Wallpaper.backdrops[root.screen?.name]?.pan.fraction ?? 0.5

        width: root.bodyWidth
        height: framing.shown ? framing.fullHeight : 0
        opacity: framing.shown ? 1 : 0
        clip: true

        Behavior on height {
            NumberAnimation {
                duration: Theme.fadeMs
                easing.type: Easing.InOutQuad
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.fadeMs
            }
        }

        Item {
            id: preview

            x: (root.bodyWidth - width) / 2
            y: root.spacing
            width: Math.round(framing.previewHeight / root.screenAspect)
            height: framing.previewHeight

            // The rest of the picture, dimmed: in reach, but not on screen.
            Image {
                anchors.fill: parent
                source: Wallpaper.current ? "file://" + Wallpaper.thumbOf(Wallpaper.current) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: Math.ceil(preview.width * root.devicePixelRatio)
                opacity: 0.35
            }

            Item {
                id: frame

                // Whole pixels, or the clip shaves the border's far edges.
                width: Math.round(preview.width / framing.zoom)
                height: Math.round(preview.height / framing.zoom)
                x: Math.round((preview.width - width) * framing.across)
                y: Math.round((preview.height - height) * Wallpaper.parallaxY)
                clip: true

                Image {
                    x: -frame.x
                    y: -frame.y
                    width: preview.width
                    height: preview.height
                    source: Wallpaper.current ? "file://" + Wallpaper.thumbOf(Wallpaper.current) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: Math.ceil(preview.width * root.devicePixelRatio)
                }

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.fg
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                function seek(y) {
                    Wallpaper.setParallaxY(Math.max(0, Math.min(1, y / height)));
                }

                onPressed: mouse => seek(mouse.y)
                onPositionChanged: mouse => {
                    if (pressed)
                        seek(mouse.y);
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
                Accessible.role: Accessible.Button
                Accessible.name: "Wallpaper colour " + root.hex
                Accessible.onPressAction: if (enabled && visible)
                    Wallpaper.setColor(root.hex)
                readonly property var keyPress: () => Wallpaper.setColor(root.hex)

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
                        name: "Wallpaper " + channel.modelData.name
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

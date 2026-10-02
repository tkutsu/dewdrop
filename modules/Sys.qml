import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// custom/sys. A thermometer reading the CPU or the card — whichever was asked
// for last — with the machine behind it in the popup.
BarItem {
    // The figure the tube stands for, and which chip it is reading.
    tooltip: Sys.temp > 0 ? `${Sys.showGpu ? "GPU" : "CPU"} ${Math.round(Sys.temp)} °C` : "No temperature sensor"
    popup: SysPopup {}

    // A temperature is only news once it is a warning, so the tube waits in
    // the drawer until the reading crosses the top of its scale.
    quiet: !Sys.hot

    // Dimmed until a sensor has answered: an empty tube is a reading of
    // nothing, and it should not look like a reading of cold.
    opacity: Sys.temp > 0 ? 1 : Theme.dimOpacity

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.fadeMs
        }
    }

    // The reading is drawn where a thermometer keeps it: a column of mercury up
    // the inside of the tube, rather than a dial around an icon or five glyphs
    // of a filling one. A temperature is a height on a scale, and this is the
    // instrument that says so — the icon is the scale, and there is only one
    // mark on it to read. The number itself is in the popup.
    //
    // Drawn here rather than taken from the symbol font, because the font's
    // thermometer had to be cut down pixel by pixel to make room for the
    // column, and a handful of rectangles are simpler than a glyph, a mask and
    // the list of where to cut. Everything is on whole pixels at the size given,
    // and the curves are drawn without antialiasing, so a one-pixel ring comes
    // out as a one-pixel ring — with it on, a nine-pixel circle is grey nearly
    // all the way round, and reads as heavier and softer than the glyphs
    // beside it, which the font hints onto the grid.
    Item {
        id: tube

        // Seven by thirteen. The tube is five wide, which leaves a three-pixel
        // bore between two one-pixel walls — a column with a pixel of dark
        // either side of it reads as a mark rising inside the tube rather than
        // the tube filling in. The bulb is a pixel wider than the tube on each
        // side: enough to be a bulb, and no more, on a bar where the icons are
        // twelve pixels tall.
        readonly property int bulb: 7
        readonly property int stem: 5
        readonly property int wall: 1
        // The row the ring would start on if it were whole. Its top arc is
        // exactly as wide as the bore, so it is not drawn: the bore runs
        // straight down into the bulb and the walls run into the ring, the way
        // the glass does.
        readonly property int join: 6
        // From the inside of the cap down to the ball: the whole run the
        // column has, which is where the service's steps land. It is a row
        // longer than the tube, because it runs on through the ring's missing
        // top row to reach the ball.
        readonly property int bore: join + 2 - wall
        // The glass is a step dimmer than the glyphs' Theme.fg. The font's
        // strokes reach fg only in their core, with a quarter-strength pixel
        // softening each edge; a wall drawn without antialiasing is all hard
        // edge, and at the same alpha it read as the whitest icon on the bar.
        readonly property color glass: Qt.rgba(1, 1, 1, 0.75)

        implicitWidth: bulb
        implicitHeight: join + bulb
        Layout.alignment: Qt.AlignVCenter
        transform: Translate {
            y: -1
        }

        // The tube, open at the bottom: it is drawn long enough to reach into
        // the bulb and clipped at the ring, so it has no bottom edge of its
        // own.
        Item {
            x: (tube.bulb - tube.stem) / 2
            width: tube.stem
            height: tube.join + 1
            clip: true

            Rectangle {
                width: tube.stem
                height: tube.join + 6
                color: "transparent"
                border.width: tube.wall
                border.color: tube.glass
                topLeftRadius: tube.stem / 2
                topRightRadius: tube.stem / 2
                antialiasing: false
            }
        }

        // The bulb, less its top row, which is clipped off (see `join`): a ring
        // with a ball inside and a gap between the two, as Font Awesome drew
        // it — the gap is what makes it a bulb with something in it rather
        // than a blob on the end of a stick.
        Item {
            y: tube.join + 1
            width: tube.bulb
            height: tube.bulb - 1
            clip: true

            Rectangle {
                y: -1
                width: tube.bulb
                height: tube.bulb
                radius: tube.bulb / 2
                color: "transparent"
                border.width: tube.wall
                border.color: tube.glass
                antialiasing: false

                // The ball is the first steps of the reading rather than part
                // of the instrument: an empty ring is a machine at the bottom
                // of the scale, and the ball fills a row at a time, from the
                // bottom, before the column starts to climb — three more steps
                // of feedback out of the same pixels.
                Rectangle {
                    readonly property int size: 3

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (parent.height + size) / 2 - height
                    width: size
                    height: Math.min(Sys.level, size)
                    visible: Sys.temp > 0
                    color: Sys.hot ? Theme.warn : Theme.fg
                }
            }
        }

        Rectangle {
            // The column stands on the ball and climbs from there to the seal,
            // one pixel a step, once the ball's three rows are full. Whole
            // pixels, top and bottom: the service steps the reading in one
            // increment per pixel of ball and bore together, and nothing is
            // animated on the way up, because half a pixel of mercury is a
            // blurred edge rather than a slower rise.
            width: 1
            height: Math.max(0, Sys.level - 3)
            x: (tube.bulb - width) / 2
            y: tube.join + 2 - height

            // Nothing to draw until something has been read — a card that has
            // not answered yet, a machine with no sensor the kernel will admit
            // to. The bottom step draws nothing either (not even the ball), so
            // the two look the same, and neither of them is a temperature worth
            // pointing at.
            visible: Sys.temp > 0
            // Past the last line the column stops being a reading and starts
            // being a warning. Pink is what the workspaces shout with.
            color: Sys.hot ? Theme.warn : Theme.fg
        }
    }

    // Left is the popup (BarItem.popupButton); right opens whichever of the
    // two the tube is reading, in the thing that shows it properly.
    // "(floating)" is a window rule in hypr/configs/wrules.lua, not part of the
    // name: it centres the window at 55% of the screen.
    actions: ({
            [Qt.RightButton]: () => {
                const tool = Sys.showGpu ? "nvtop" : "btop";
                Quickshell.execDetached(Settings.inTerminal([tool], tool + " (floating)"));
            }
        })
}

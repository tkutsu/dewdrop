import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Hyprland
import qs
import qs.components

// The handle of the right pill's drawer: the modules with nothing to say right
// now — no unread mail, no updates, the tools that are never news — fold away
// behind it, and a click brings them back out to its left. The bar then shows
// what is true at the moment, and the rest is one click from it.
//
// The modules decide for themselves whether they are quiet (BarItem.quiet);
// this only says whether the drawer is open. Bar.qml puts the two together.
BarItem {
    id: root

    property bool open: false
    // Whether anything is in the drawer. The handle is only there while it
    // holds something — a chevron that opened onto nothing would be a control
    // for its own sake.
    property bool holding: false
    // Whether the pointer is anywhere on the bar or in one of its popups.
    property bool pointerNear: false

    present: holding
    tooltip: open ? "Show less" : "Show more"

    // A pixel less air on its right than the row gives: at the full gap the
    // chevron read as set apart from the icon beside it.
    Layout.rightMargin: -1
    onHoldingChanged: if (!holding)
        open = false

    // One chevron that turns over rather than two glyphs swapped, and turns
    // as the fold comes to rest rather than alongside it: the modules move,
    // then the handle answers, pointing the way they will go back.
    //
    // Eased in and out: a thing turned by hand gathers speed and brakes into
    // place, where an ease-out set off at full speed and read as a flick. It
    // starts once the modules have landed (Theme.foldLandMs),
    // and turns while the glass settles, one gesture handed on without a
    // pause. Starting earlier (70% of the way through the old eased fold was
    // tried) put most of the turn where the eye was still on the modules,
    // and it went by unseen.
    property real turned: 0

    onOpenChanged: turn.restart()

    SequentialAnimation {
        id: turn

        PauseAnimation {
            duration: Theme.foldLandMs
        }
        NumberAnimation {
            target: root
            property: "turned"
            to: root.open ? 1 : 0
            duration: Theme.turnMs
            easing.type: Easing.InOutCubic
        }
    }

    // Drawn rather than taken from the symbol font, the way SF Symbols draws
    // it: two strokes meeting at a point, round at the ends and at the join.
    // The font's chevron is a filled outline eight pixels tall and a pixel and
    // a third thick, and the only smaller one it has is thinner still. This
    // one is a pixel shorter and narrower and half as thick again, and opens
    // wider than a right angle, as Apple's does.
    //
    // Symmetric about its own middle, so the half turn lands the ink on the
    // rows and columns it started on (the font's glyph, turned about its box,
    // came to rest a pixel high).
    Item {
        id: chevron

        readonly property real stroke: 2
        // From the point to the end of either arm: up or down, and across.
        readonly property real reach: 2.5
        readonly property real depth: 2

        Layout.fillHeight: true
        implicitWidth: depth + stroke

        Shape {
            id: mark

            width: chevron.depth + chevron.stroke
            height: 2 * chevron.reach + chevron.stroke
            y: (chevron.height - height) / 2
            preferredRendererType: Shape.CurveRenderer
            transform: Rotation {
                origin.x: mark.width / 2
                origin.y: mark.height / 2
                angle: 180 * root.turned
            }

            ShapePath {
                strokeColor: Theme.handle
                strokeWidth: chevron.stroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: chevron.stroke / 2 + chevron.depth
                startY: chevron.stroke / 2

                PathLine {
                    x: chevron.stroke / 2
                    y: chevron.stroke / 2 + chevron.reach
                }
                PathLine {
                    x: chevron.stroke / 2 + chevron.depth
                    y: chevron.stroke / 2 + 2 * chevron.reach
                }
            }
        }
    }

    actions: ({
            [Qt.LeftButton]: () => {
                root.open = !root.open;
            }
        })

    // A drawer left open is the whole bar again, so it shuts itself once the
    // pointer has been off the bar for a moment — the way a menu bar folds
    // its extras back when you are done with them. A popup counts as the bar,
    // so reading one never folds the modules away from under it.
    Timer {
        running: root.open && !root.pointerNear
        interval: 4000
        onTriggered: root.open = false
    }

    // And at once on a click anywhere off the bar and its popups: the same
    // custom>>click from Hyprland that closes a popup (see OpenPopup.qml),
    // which still hands the click on to whatever it landed on. Clicks on the
    // bar itself are Bar.qml's.
    Connections {
        target: Hyprland
        enabled: root.open

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "custom" && event.data === "click" && PopupPointer.hovered === 0 && PopupPointer.bars === 0)
                root.open = false;
        }
    }
}

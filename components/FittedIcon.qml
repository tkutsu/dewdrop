import QtQuick
import Quickshell.Widgets
import qs
import qs.services

// Fit artwork to its visible ink and expose the measured dimensions.

Item {
    id: root

    property alias source: image.source
    property alias status: image.status
    // Fading variants share one reference so opacity never changes their geometry.
    property string layoutSource: image.source
    // How large the artwork is asked to be drawn...
    property int size: Theme.iconSize
    // ...and how much room the item takes, which stays put so a row of icons
    // keeps its rhythm even when one of them is drawn smaller than the rest.
    property int box: Theme.iconSize

    // How tall an icon's ink should come out, as a fraction of that. Set it and
    // the size above becomes a ceiling rather than the answer: an icon carrying
    // less headroom than the theme's convention is drawn smaller so it stands
    // the same height as everything beside it. Zero turns the whole thing off.
    property real ink: 0
    // Off for artwork already drawn at its size (a cut from the icon font):
    // the ink is still measured for layout, but never resizes it. A set whose
    // parts fade in, like the volume speaker's waves, would otherwise measure
    // taller once a wave was bright enough to count, and come out smaller.
    property bool fitsInk: true

    // A new icon is a new question, and an icon seen before is not a question
    // at all. Nothing else restarts it — the answer resizes the thing it was
    // measured from, so a probe that re-ran on every change would chase its own
    // tail down to nothing.
    readonly property string measureKey: root.ink > 0 ? root.layoutSource : ""
    readonly property real extent: root.measureKey ? Ink.extentOf(root.measureKey) : 0

    // Measured on a copy in Ink's own window, at the size it is asked for here
    // (before any shrink), so this item can come and go mid-measurement.
    onMeasureKeyChanged: Ink.measureIcon(root.measureKey, root.size)
    Component.onCompleted: Ink.measureIcon(root.measureKey, root.size)

    // Where the ink sits across the item, in whole pixels: its first column
    // from the item's left edge, and how many columns it spans. The whole box
    // until it has been measured, so a caller laying the icon out on its ink
    // starts from exactly where it would have been without.
    readonly property var span: root.measureKey ? Ink.spanOf(root.measureKey) : null
    readonly property int inkX: span ? artwork.restX + Math.round(root.drawn * span.left) : 0
    readonly property int inkWidth: span ? artwork.restX + Math.round(root.drawn * span.right) - inkX : box

    // Shrink only. Ink cannot be taller than the box holding it, so the target
    // is a floor as well as a target: nothing comes out under it, and the cap
    // is what stops an icon drawn with headroom to spare from being blown up
    // past its own pixel grid — which costs more in a soft icon than the
    // evenness buys back, and would stretch a deliberately short, wide icon
    // into its neighbours.
    readonly property int drawn: {
        if (!root.fitsInk || root.ink <= 0 || root.extent <= 0)
            return root.size;
        return Math.min(root.size, Math.round(root.size * root.ink / root.extent));
    }

    // How far towards a larger size the artwork is drawn, 0..1, about its
    // centre, and that size in pixels. Placed on whole pixels, half a pixel
    // off centre when it grows by an odd count. Rastered at the larger size the moment it sets
    // off, because a raster scaled either way blurs: sharp at both ends, and
    // only soft while it moves. Measurements and layout keep to `drawn`.
    property real magnify: 0
    property int magnifiedSize: drawn

    implicitWidth: box
    implicitHeight: box

    // Keep artwork separate from the measurements exposed by this item.
    Item {
        id: artwork

        readonly property int raster: root.magnify > 0 ? root.magnifiedSize : root.drawn

        // Placed by hand rather than by anchors: centring a 13px icon in a 17px
        // box gives a half pixel, and half a pixel is a blurred icon. Where
        // the artwork sits at its own size, which the ink is measured from.
        readonly property int restX: Math.floor((root.implicitWidth - root.drawn) / 2)
        x: restX - Math.floor((raster - root.drawn) / 2)
        y: Math.floor((root.implicitHeight - root.drawn) / 2) - Math.floor((raster - root.drawn) / 2)
        width: raster
        height: raster
        scale: (root.drawn + (root.magnifiedSize - root.drawn) * root.magnify) / raster

        IconImage {
            id: image
            anchors.fill: parent
        }
    }
}

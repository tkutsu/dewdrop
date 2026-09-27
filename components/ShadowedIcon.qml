import QtQuick
import Quickshell.Widgets
import qs
import qs.services

// style.css puts "-gtk-icon-shadow: 1px 1px 0 rgba(0, 0, 0, 0.2)" on the tray
// and on the workspace taskbar. MultiEffect pads the layer it renders into by
// default, which shrinks the icon inside its own box — so the padding is turned
// off and the room for the 1px offset is given by the wrapper instead.
Item {
    id: root

    property alias source: image.source
    property alias status: image.status
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

    // A new icon is a new question, and an icon seen before is not a question
    // at all. Nothing else restarts it — the answer resizes the thing it was
    // measured from, so a probe that re-ran on every change would chase its own
    // tail down to nothing.
    readonly property string measureKey: root.ink > 0 ? String(image.source) : ""
    readonly property real extent: root.measureKey ? IconInk.extentOf(root.measureKey) : 0

    // The probe is temporary by design: it comes into being only while there is
    // a measurement outstanding and goes as soon as there is not, so a settled
    // bar is carrying no canvases, no grabs and no textures for any of this.
    Loader {
        active: root.measureKey !== "" && root.extent <= 0 && image.status === Image.Ready

        // Off `bounds` rather than `measured`, so the height and the span land
        // in one go: the height alone is what retires this probe, and it would
        // be gone before the span it had also found was heard.
        sourceComponent: InkProbe {
            target: image
            ready: true
            onBounds: (top, bottom, left, right, edgeLeft, edgeRight) => IconInk.remember(root.measureKey, (bottom - top + 1) / height, edgeLeft / width, (edgeRight + 1) / width)
        }
    }

    // Where the ink sits across the item, in whole pixels: its first column
    // from the item's left edge, and how many columns it spans. The whole box
    // until it has been measured, so a caller laying the icon out on its ink
    // starts from exactly where it would have been without.
    readonly property var span: root.measureKey ? IconInk.spanOf(root.measureKey) : null
    readonly property int inkX: span ? artwork.x + Math.round(root.drawn * span.left) : 0
    readonly property int inkWidth: span ? artwork.x + Math.round(root.drawn * span.right) - inkX : box

    // Shrink only. Ink cannot be taller than the box holding it, so the target
    // is a floor as well as a target: nothing comes out under it, and the cap
    // is what stops an icon drawn with headroom to spare from being blown up
    // past its own pixel grid — which costs more in a soft icon than the
    // evenness buys back, and would stretch a deliberately short, wide icon
    // into its neighbours.
    readonly property int drawn: {
        if (root.ink <= 0 || root.extent <= 0)
            return root.size;
        return Math.min(root.size, Math.round(root.size * root.ink / root.extent));
    }

    // One spare pixel for the 1px drop shadow to land in.
    implicitWidth: box
    implicitHeight: box

    // The shadow rides a wrapper rather than the icon itself, so that the
    // picture the probe takes of the icon is of the icon: a layer on the thing
    // being grabbed hands back the effect's output instead, and a shadow one
    // pixel below the artwork would have measured as one more pixel of artwork.
    Item {
        id: artwork

        // Placed by hand rather than by anchors: centring a 13px icon in a 17px
        // box gives a half pixel, and half a pixel is a blurred icon.
        x: Math.floor((root.implicitWidth - root.drawn) / 2)
        y: Math.floor((root.implicitHeight - root.drawn) / 2)
        width: root.drawn
        height: root.drawn

        IconImage {
            id: image
            anchors.fill: parent
        }
    }
}

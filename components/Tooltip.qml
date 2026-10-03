import QtQuick
import Quickshell
import qs

// A module's tooltip, drawn the way the Mac draws a help tag: a line of small
// type in a snug box, smaller than a popover in every measure — type, padding,
// corner and shadow — so it reads as a note on the thing under the pointer
// rather than as somewhere to go.
Popup {
    id: root

    property alias text: label.text

    hPadding: 7
    vPadding: 3
    radius: Theme.tagRadius
    shadowBlur: 8
    shadowY: 2
    // A tag fades in where it is; only a popover grows out of its pill.
    grows: false
    probes: false

    // Nothing to point at, so the pointer goes through it: a tag is never in
    // the way of what is under it, and never holds itself open.
    mask: Region {}

    PopupText {
        id: label
        // Tooltips carried newlines in waybar (the updater's two lines, mpd's
        // five); nothing in them was ever markup.
        textFormat: Text.PlainText
        font.pixelSize: Theme.captionSize
        lineHeight: 1.2
        // A tag is a phrase, but a tray app writes what it likes into its
        // own; past this it wraps rather than running across the bar.
        width: Math.min(implicitWidth, 280)
        wrapMode: Text.Wrap
        // Qt hangs proportional leading below every line, the last one included,
        // so the 1.2 that spaces the multi-line tooltips also hands the popup a
        // line's worth of empty at the bottom and nothing at the top. Give back
        // the trailing line's share; the ink sits above it, so nothing is
        // clipped, and what is left is the font's own ascent-to-descent box,
        // which the popup's padding then sits evenly around.
        //
        // Rounded as a whole rather than only the part taken off: an implicit
        // height of 19.2 less 3 is a popup 0.2 of a pixel too tall, and the
        // surface swallows that fraction at the bottom edge alone — which is
        // the one pixel that made the top look like the bigger of the two.
        height: Math.round(implicitHeight - metrics.height * (lineHeight - 1))

        FontMetrics {
            id: metrics
            font: label.font
        }
    }
}

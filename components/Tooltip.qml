import QtQuick
import qs

// A plain text popup: what every "tooltip": true module used to get from GTK.
Popup {
    id: root

    property alias text: label.text

    PopupText {
        id: label
        // Tooltips carried newlines in waybar (the updater's two lines, mpd's
        // five); nothing in them was ever markup.
        textFormat: Text.PlainText
        lineHeight: 1.2
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

import QtQuick
import qs

// The label preset every popup body was spelling out by hand: white, the body
// face, at the tooltip size style.css gave them. Anything that differs — mono
// figures, a bold header, a dimmed line — says only what differs.
//
// Weight is deliberately left alone. The popups all asked for Font.Normal by
// name, which is Text's own default, and a weight set here would be a second
// opinion for `font.bold` to argue with in the few places that want one.
Text {
    color: Theme.fg
    font.family: Theme.bodyFont
    font.pixelSize: Theme.popupTextSize
    // Tabular figures, so a readout keeps its width as it counts — which is
    // what the monospace face used to be here for.
    font.features: Theme.figures
}

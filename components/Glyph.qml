import QtQuick
import qs

// A BarText preset for Nerd Font icons: symbol font, optically centred, laid
// out on its ink, and unweighted (the icon fonts have a single weight, so
// Medium only blurs them).
BarText {
    family: Theme.glyphFont
    weight: Font.Normal
    opticalCentre: true
    tightWidth: true
    fontSize: Theme.glyphSize
}

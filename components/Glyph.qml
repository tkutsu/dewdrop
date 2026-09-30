import QtQuick
import qs

// A BarText preset for Nerd Font icons: symbol font, optically centred, laid
// out on its ink, and unweighted (the icon fonts have a single weight, so
// Medium only blurs them).
//
// Or a drawing, when Theme.glyph holds a file rather than a codepoint (see
// Theme.panel). Every caller passes whatever the table holds, so which of the
// two a slot shows is decided there once rather than at each of them.
Item {
    id: root

    property string text
    property int fontSize: Theme.glyphSize
    property color color: Theme.fg
    property real nudge: 0
    property bool tightWidth: true

    readonly property bool drawing: text.startsWith("file:")
    readonly property bool fontCut: text.endsWith("#em")

    // What is on screen, which is `text` except while a drawing the bar has
    // never measured is being measured. Shown straight away, it came in at
    // its whole box and shrank onto its ink a frame later, a zoom and a jolt
    // of the pill the first time caffeine went on or the volume reached a new
    // step. So the old picture stays until `pending` has the new one's size.
    property string shown

    function settle() {
        if (!root.drawing || pending.extent > 0)
            root.shown = root.text;
    }

    // Later rather than now: `pending` hears of the new text through a chain
    // of bindings, and read in the middle of it would still be answering for
    // the old one.
    onTextChanged: Qt.callLater(root.settle)
    Component.onCompleted: settle()

    // A drawing is laid out on its ink too, like the font's glyphs, rather
    // than on the square box it is drawn in: the launcher's 12px magnifier
    // sat in 18px of box and stood three pixels further from its neighbours
    // than the glyphs between them stood from each other.
    implicitWidth: !drawing ? label.implicitWidth : tightWidth ? art.inkWidth : art.implicitWidth
    implicitHeight: Theme.barHeight
    baselineOffset: label.baselineOffset

    BarText {
        id: label
        visible: !root.drawing
        width: implicitWidth
        height: parent.height
        text: root.drawing ? "" : root.text
        family: Theme.glyphFont
        weight: Font.Normal
        opticalCentre: true
        tightWidth: root.tightWidth
        fontSize: root.fontSize
        color: root.color
        nudge: root.nudge
    }

    // Scaled with the font size it stands in for, so a popup's smaller glyphs
    // get smaller drawings. An SVG cannot take the colour, but every colour a
    // glyph is given is white at some alpha, so the alpha is what carries over.
    ShadowedIcon {
        id: art
        visible: root.drawing
        x: root.tightWidth ? -inkX : 0
        y: Math.floor((root.height - height) / 2) + root.nudge
        source: root.drawing ? root.shown : ""
        // A cut from the font (Theme.fontCut) is drawn at the font size and
        // left there, as big as the glyph it came from.
        size: root.fontCut ? root.fontSize : Math.round(root.fontSize * Theme.iconSize / Theme.glyphSize)
        box: size
        ink: Theme.glyphInk
        fitsInk: !root.fontCut
        opacity: root.color.a
    }

    // The next drawing, drawn unseen at the same size so InkProbe can measure
    // it (a grab ignores the opacity above what it grabs). Empty once shown,
    // so a settled glyph holds one picture, not two.
    ShadowedIcon {
        id: pending
        opacity: 0
        source: root.drawing && root.text !== root.shown ? root.text : ""
        size: art.size
        ink: art.ink
        onExtentChanged: Qt.callLater(root.settle)
    }
}

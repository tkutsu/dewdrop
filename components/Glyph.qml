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

    implicitWidth: drawing ? art.implicitWidth : label.implicitWidth
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
        y: Math.floor((root.height - height) / 2) + root.nudge
        source: root.drawing ? root.text : ""
        size: Math.round(root.fontSize * Theme.iconSize / Theme.glyphSize)
        box: size
        ink: Theme.glyphInk
        opacity: root.color.a
    }
}

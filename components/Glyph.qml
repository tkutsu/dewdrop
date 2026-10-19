import QtQuick
import qs
import qs.services

// A BarText preset for Nerd Font icons: symbol font, optically centred, laid
// out on its ink, and unweighted (the icon fonts have a single weight, so
// Medium only blurs them).
//
// Or a drawing, when Theme.glyph holds a file rather than a codepoint (see
// Theme.panel). Every caller passes whatever the table holds, so which of the
// two a slot shows is decided there once rather than at each of them.
Item {
    id: root
    transform: ModuleIconScale { icon: root }

    property string text
    // Optional shared geometry for drawings whose parts differ only in opacity.
    property string layoutSource: ""
    property int fontSize: Theme.glyphSize
    property color color: Theme.fg
    property color inkColor: Theme.barInk(root, root.color, true)

    Behavior on inkColor {
        ColorAnimation { duration: Theme.fadeMs; easing.type: Easing.InOutQuad }
    }
    property real nudge: 0
    property bool tightWidth: true

    readonly property bool drawing: text.startsWith("file:")
    readonly property bool fontCut: shown.endsWith("#em")
    readonly property bool shownDrawing: shown.startsWith("file:")

    // What is on screen, which is `text` except while a drawing the bar has
    // never measured is being measured. Shown straight away, it came in at
    // its whole box and shrank onto its ink a frame later, a zoom and a jolt
    // of the pill the first time caffeine went on or the volume reached a new
    // step. So the old picture stays until Ink has the new one's size.
    property string shown

    // Off `text` itself rather than `drawing`: this runs from onTextChanged,
    // which can come before that binding has heard of the new text.
    function settle() {
        const source = root.layoutSource || root.text;
        if (!root.text.startsWith("file:") || Ink.extentOf(source) > 0)
            root.shown = root.text;
        else
            Ink.measureIcon(source, root.text.endsWith("#em") ? root.fontSize : Math.round(root.fontSize * Theme.iconSize / Theme.glyphSize));
    }

    onTextChanged: settle()
    onLayoutSourceChanged: settle()
    Component.onCompleted: settle()

    Connections {
        target: Ink
        enabled: root.shown !== root.text

        function onRevisionChanged() {
            root.settle();
        }
    }

    // A drawing is laid out on its ink too, like the font's glyphs, rather
    // than on the square box it is drawn in: the launcher's 12px magnifier
    // sat in 18px of box and stood three pixels further from its neighbours
    // than the glyphs between them stood from each other.
    implicitWidth: !shownDrawing ? label.implicitWidth : tightWidth ? (art.item?.inkWidth ?? 0) : art.implicitWidth
    implicitHeight: Theme.barHeight
    baselineOffset: label.baselineOffset

    BarText {
        id: label
        visible: !root.shownDrawing
        width: implicitWidth
        height: parent.height
        text: root.shownDrawing ? "" : root.shown
        family: Theme.glyphFont
        weight: Font.Normal
        opticalCentre: true
        tightWidth: root.tightWidth
        fontSize: root.fontSize
        color: root.color
        inkColor: root.inkColor
        nudge: root.nudge
    }

    // Scaled with the font size it stands in for, so a popup's smaller glyphs
    // get smaller drawings. An SVG cannot take the colour, but every colour a
    // glyph is given is white at some alpha, so the alpha is what carries over.
    Loader {
        id: art
        active: root.shownDrawing
        x: root.tightWidth ? -(item?.inkX ?? 0) : 0
        y: Math.floor((root.height - height) / 2) + root.nudge
        opacity: root.inkColor.a

        sourceComponent: FittedIcon {
            source: root.shownDrawing ? root.shown : ""
            layoutSource: root.layoutSource || source
            // A cut from the font stays at the font size rather than fitting its ink.
            size: root.fontCut ? root.fontSize : Math.round(root.fontSize * Theme.iconSize / Theme.glyphSize)
            box: size
            ink: Theme.glyphInk
            fitsInk: !root.fontCut
        }
    }
}

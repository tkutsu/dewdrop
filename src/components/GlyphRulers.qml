import QtQuick

// As wide as the widest of a set of glyphs, for a Glyph that keeps room for
// every one it can show (Glyph.alternates). Drawn at no opacity rather than
// hidden, because a hidden glyph is never measured (see BarText) and would
// report the font's own guess at its width instead of its pixels.
Column {
    id: root

    property var glyphs: []
    property int fontSize
    property bool tightWidth: true

    opacity: 0

    Repeater {
        model: root.glyphs

        // By address: QML will not have a type inside itself, and these are
        // inside the Glyph they measure for.
        Loader {
            id: ruler

            required property string modelData

            source: "Glyph.qml"

            Binding { target: ruler.item; property: "text"; value: ruler.modelData }
            Binding { target: ruler.item; property: "fontSize"; value: root.fontSize }
            Binding { target: ruler.item; property: "tightWidth"; value: root.tightWidth }
        }
    }
}

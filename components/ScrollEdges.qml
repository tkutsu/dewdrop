import QtQuick
import qs

// A scrolling view's soft edges: content on its way past the top or bottom
// fades out rather than being cut off at the view's edge (shaders/edge.frag).
// Each edge fades only while there is more beyond it, and in step with how
// far there is, so a list at rest at its start is drawn untouched and the top
// edge softens as it scrolls away rather than switching on.
//
// The view's layer effect:
//
//     layer.enabled: interactive
//     layer.effect: ScrollEdges { view: list }
ShaderEffect {
    required property Flickable view
    property real reach: Theme.scrollEdge

    readonly property real span: height
    // How far the content has run on past each edge, margins and all: a view
    // padded inside (SettingsMenu's) softens as soon as a row enters the
    // padding rather than once it has crossed it.
    readonly property real fadeTop: Math.min(reach, Math.max(0, view.contentY - view.originY + view.topMargin))
    readonly property real fadeBottom: Math.min(reach, Math.max(0, view.originY + view.contentHeight + view.bottomMargin - view.height - view.contentY))

    fragmentShader: Qt.resolvedUrl("../shaders/edge.frag.qsb")
}

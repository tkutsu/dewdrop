import QtQuick
import qs
import "../Drops.js" as Drops

// A pill arriving beside a neighbour, with contents and input following its glass.
Pill {
    id: root
    required property Item control
    property real morphValue: 0
    readonly property var geometry: Drops.geometry(Theme)

    edges: false
    drawsSlab: false
    // With nothing to show there is no pill, rather than an empty one. Off
    // the module's `reveal` rather than its visibility: hiding an item hides
    // its children with it, so a pill reading its child's `visible` would
    // latch shut the first time the module was quiet.
    visible: root.control.reveal > 0
    contentOpacity: root.geometry.contents(root.control.reveal) * root.geometry.morphContents(root.morphValue)
    contentScale: root.geometry.morph(Qt.vector4d(0, 0, width, Theme.barHeight), root.morphValue).z / Math.max(width, 1)
    contentSink: Theme.barHeight * Math.max(0, (root.morphValue - 0.5) / 1.5)
    interactive: root.morphValue <= 0
    trackOpacity: contentOpacity
    trackReady: root.control.reveal === 1 && root.morphValue === 0
}

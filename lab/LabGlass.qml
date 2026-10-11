import QtQuick
import qs.components

// Liquid drawn with the lab's copy of its shader (lab/glass.frag), which the
// prototypes change freely. Its press, light and hover are Liquid's own,
// which the scenes set by hand.
Liquid {
    fragmentShader: Qt.resolvedUrl("glass.frag.qsb")
}

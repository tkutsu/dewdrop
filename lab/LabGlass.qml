import QtQuick
import qs.components

// Liquid with the lab's two extra lights (lab/glass.frag): a press, and the
// pointer. Both off by default, which draws exactly what Liquid draws.
Liquid {
    property vector4d press: Qt.vector4d(0, 0, 1, 0)
    property vector4d light: Qt.vector4d(0, 0, 0, 0)

    fragmentShader: Qt.resolvedUrl("glass.frag.qsb")
}

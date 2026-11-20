import QtQuick
import qs.src.core

// The hairline between a popup's sections, and between a menu's groups. As
// wide as the rows' fill rather than the box, so it lines up
// with the highlight. Whoever places one gives it a width.
Rectangle {
    implicitHeight: Theme.pillBorder
    color: Theme.stroke
    Accessible.ignored: true
}

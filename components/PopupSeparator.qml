import QtQuick
import qs

// The hairline between a popup's sections, and between a menu's groups. As
// wide as the rows' fill rather than the box: the Mac has inset its menus'
// lines to the highlight since Big Sur. Whoever places one gives it a width.
Rectangle {
    implicitHeight: Theme.pillBorder
    color: Theme.stroke
    Accessible.ignored: true
}

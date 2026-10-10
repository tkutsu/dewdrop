import QtQuick
import qs

// The mark of the bar's selection mode (OpenPopup.selected) on the item it
// is on: the ring a popup draws round a control the keys are on, as a
// capsule to sit in the pill. Laid in the selected item itself, so it moves
// with it; gone while the keys are down in the item's popup, which marks
// its own control instead.
Rectangle {
    // What it goes round: the item, or a child narrower than it (a module's
    // contents without its gap padding).
    property Item box: parent
    readonly property int pad: 4

    visible: OpenPopup.selected === parent && !OpenPopup.inPopup
    x: (box === parent ? 0 : box.x) - pad
    width: box.width + 2 * pad
    height: Theme.barHeight - 2 * pad
    y: (parent.height - height) / 2
    z: 2
    radius: height / 2
    color: "transparent"
    border.width: 1.5
    border.color: Theme.outlineHover
}

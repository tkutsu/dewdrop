import QtQuick
import Quickshell

// Mirror a bar item's geometry into its separate Top popup host. Popups of
// other windows, including submenus, keep their original anchor and parent.
Item {
    id: root
    property Item owner: null
    readonly property var host: owner?.QsWindow.window?.popupHost ?? null
    parent: host?.contentItem ?? null
    readonly property point ownerPosition: {
        let x = 0, y = 0;
        for (let item = root.owner; item; item = item.parent) {
            x += item.x;
            y += item.y;
        }
        return Qt.point(x, y);
    }
    x: ownerPosition.x
    y: ownerPosition.y
    width: owner?.width ?? 0
    height: owner?.height ?? 0
}

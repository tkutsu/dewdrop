import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.components

// idle_inhibitor. Native wayland protocol, so unlike every other module here
// there is no process behind it at all.
BarItem {
    id: root

    property var inhibitWindow: null
    readonly property bool active: Caffeine.active
    Component.onCompleted: {
        root.inhibitWindow = QsWindow.window;
        Caffeine.attach(root.inhibitWindow);
    }
    Component.onDestruction: Caffeine.detach(root.inhibitWindow)

    tooltip: active ? "Caffeine on" : "Caffeine off"
    quiet: !active

    Glyph {
        Layout.fillHeight: true
        text: root.active ? Theme.glyph.idleOn : Theme.glyph.idleOff
        fontSize: Theme.glyphSizeLarge + 1
    }

    actions: ({
            [Qt.LeftButton]: () => {
                Caffeine.active = !Caffeine.active;
            }
        })
}

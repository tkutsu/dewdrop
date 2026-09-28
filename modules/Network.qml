import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// The connection, where nm-applet's tray icon was: the cone filling with the
// signal, or the cable, dimmed with neither. The networks are in the popup;
// right click is the Wi-Fi radio.
BarItem {
    id: root

    settingsKey: "network"
    popup: NetworkPopup {}

    opacity: Network.online ? 1 : Theme.dimOpacity

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.fadeMs
        }
    }

    // A pixel less air either side of the cone than the row gives: it is
    // widest at its top edge and a point at the bottom, so most of its
    // height stands well in from the ink box, and at the full gap it read as
    // set apart from both neighbours. Kept from the tray, which measured it.
    readonly property bool cone: !Network.wiredUp
    Layout.leftMargin: Theme.gap - (cone ? 1 : 0)
    Layout.rightMargin: cone ? -1 : 0

    Glyph {
        Layout.fillHeight: true
        text: Network.icon
        fontSize: Theme.trayGlyphSize
    }

    actions: ({
            [Qt.RightButton]: () => Network.toggleWifi()
        })
}

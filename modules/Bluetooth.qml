import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// Bluetooth, where blueman-applet's tray icon was: the rune, struck through
// and dimmed while the radio is off, with the devices in the popup. Right
// click is the radio, the way a right click on the bell is do not disturb.
BarItem {
    id: root

    settingsKey: "bluetooth"
    present: Bluetooth.present
    popup: BluetoothPopup {}

    opacity: Bluetooth.on ? 1 : Theme.dimOpacity

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.fadeMs
        }
    }

    // The tray's size for the glyphs it drew in place of an applet's
    // artwork, so the rune is the one it replaces to the pixel.
    Glyph {
        Layout.fillHeight: true
        text: Bluetooth.icon
        fontSize: Theme.trayGlyphSize
    }

    actions: ({
            [Qt.RightButton]: () => Bluetooth.toggle()
        })
}

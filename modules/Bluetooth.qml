import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// Bluetooth, where blueman-applet's tray icon was: the rune, struck through
// and dimmed while the radio is off, with the devices in the popup. Left click
// is blueman's manager, for what the popup cannot do (a PIN, a device's own
// settings) and for when it gets something wrong; opening it brings blueman's
// agent back over D-Bus, and the tray keeps that one's icon out of the row.
// Right click is the radio, the way a right click on the bell is do not
// disturb.
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

    // Left is the popup (BarItem.popupButton).
    actions: ({
            [Qt.RightButton]: () => Bluetooth.toggle()
        })
}

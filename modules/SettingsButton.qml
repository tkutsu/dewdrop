import QtQuick
import QtQuick.Layouts
import qs
import qs.components

// The cog at the head of the right pill. Opens the settings page
// (modules/SettingsPage.qml); a second click closes it.
BarItem {
    tooltip: Settings.shown ? "" : "Settings"

    Glyph {
        Layout.fillHeight: true
        text: Theme.glyph.settings
    }

    onClicked: function (mouse) {
        if (mouse.button === Qt.LeftButton)
            Settings.toggle();
    }
}

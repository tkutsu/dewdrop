import QtQuick
import QtQuick.Layouts
import qs
import qs.components

// The cog, first in the right pill's drawer. Opens the settings page
// (modules/SettingsPage.qml); a second click closes it. Never news, so it
// stays in the drawer unless pinned out with a middle click.
BarItem {
    quiet: true
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

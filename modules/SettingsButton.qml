import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// The gear: opens the settings window. A tool, never news, so it waits in
// the drawer unless it is pinned out.
BarItem {
    quiet: true
    tooltip: "Settings"

    Glyph {
        Layout.fillHeight: true
        text: Theme.glyph.settings
        fontSize: Theme.glyphSizeLarge
    }

    actions: ({
            [Qt.LeftButton]: () => Preferences.toggle()
        })
}

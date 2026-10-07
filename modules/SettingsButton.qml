import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// The tools: opens the settings window. A tool, never news, so it waits in
// the drawer unless it is pinned out.
BarItem {
    quiet: true
    tooltip: "Settings"

    // Two under the large size: Octicons' tools ink taller than the
    // Material glyphs beside them.
    Glyph {
        Layout.fillHeight: true
        text: Theme.glyph.settings
        fontSize: Theme.glyphSizeLarge - 2
    }

    actions: ({
            [Qt.LeftButton]: () => Preferences.toggle()
        })
}

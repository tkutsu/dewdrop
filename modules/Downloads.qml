import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// Opens the downloads folder. Out of the drawer while something in there has
// not been opened yet.
BarItem {
    quiet: Downloads.unopened.length === 0
    name: "Downloads"
    tooltip: Downloads.summary

    BadgedGlyph {
        Layout.fillHeight: true
        glyph: Theme.glyph.downloads
        glyphSize: Theme.glyphSizeLarge
        badge: Settings.badgeStyle("downloads") === "hide" ? "" : Downloads.label
        dot: Settings.badgeStyle("downloads") === "dot"
        underdot: Settings.badgeStyle("downloads") === "underdot"
    }

    actions: ({
            [Qt.LeftButton]: () => Downloads.open(),
            [Qt.RightButton]: () => Downloads.clear()
        })
}

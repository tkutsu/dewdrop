import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components

// The chosen capture command owns selection, editing, saving and the clipboard.
BarItem {
    present: Settings.screenshotCommand !== ""

    // A tool, never news: it waits in the drawer unless it is pinned out.
    quiet: true
    tooltip: "Screenshot"

    Glyph {
        Layout.fillHeight: true
        text: Theme.glyph.satty
        fontSize: Theme.glyphSizeLarge
    }

    actions: ({
            [Qt.LeftButton]: () => {
                if (Settings.screenshotCommand !== "")
                    Quickshell.execDetached(["sh", "-c", Settings.screenshotCommand]);
            }
        })
}

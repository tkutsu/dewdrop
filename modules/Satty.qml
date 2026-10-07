import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components

// custom/satty. taskbar-satty.sh owns the flock that makes the keybind and the
// bar click toggle the same screenshot flow, and the choice between a quick
// copy and the editor: the button the region is dragged with.
BarItem {
    readonly property string script: Paths.script("taskbar-satty.sh")

    // A tool, never news: it waits in the drawer unless it is pinned out.
    quiet: true
    tooltip: "Screenshot"

    Glyph {
        Layout.fillHeight: true
        text: Theme.glyph.satty
        fontSize: Theme.glyphSizeLarge
    }

    actions: ({
            [Qt.LeftButton]: () => Quickshell.execDetached([script])
        })
}

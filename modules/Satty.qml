import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components

// custom/satty. taskbar-satty.sh stays as-is — it owns the flock that makes the
// keybind and the bar click toggle the same screenshot flow.
BarItem {
    readonly property string script: Quickshell.env("HOME") + "/_scripts/taskbar-satty.sh"

    // A tool, never news: it waits in the drawer unless it is pinned out.
    quiet: true

    Glyph {
        Layout.fillHeight: true
        text: Theme.glyph.satty
        fontSize: Theme.glyphSizeLarge
    }

    actions: ({
            [Qt.LeftButton]: () => Quickshell.execDetached([script]),
            [Qt.RightButton]: () => Quickshell.execDetached([script, "fast"])
        })
}

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components

// custom/satty. taskbar-satty.sh stays as-is — it owns the flock that makes the
// keybind and the bar click toggle the same screenshot flow.
BarItem {
    readonly property string script: Quickshell.env("HOME") + "/_scripts/taskbar-satty.sh"


    Glyph {
        Layout.fillHeight: true
        text: Theme.glyph.satty
        fontSize: Theme.glyphSizeLarge
    }

    onClicked: function (mouse) {
        Quickshell.execDetached(mouse.button === Qt.RightButton ? [script, "fast"] : [script]);
    }
}

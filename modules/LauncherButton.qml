import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// custom/launcher: the bar's button, not the launcher itself — that is
// services/Launcher.qml and modules/LauncherMenu.qml. Named apart from them so
// that Bar.qml, which imports qs.modules and qs.services both, has one Launcher
// to resolve rather than two.
//
// The dummy `exec`/`interval: once` the waybar version needed (a custom module
// with no output gets hidden) has no equivalent here.
BarItem {

    Glyph {
        Layout.fillHeight: true
        text: Theme.glyph.launcher
    }

    onClicked: function (mouse) {
        // Left opens the launcher, right the power menu — as it always was,
        // except both are ours now rather than rofi modes. Both toggle, so a
        // second click closes what the first opened.
        if (mouse.button === Qt.RightButton)
            Power.toggle();
        else
            Launcher.toggle();
    }
}

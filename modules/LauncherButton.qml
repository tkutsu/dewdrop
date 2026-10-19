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
    tooltip: "Search"

    Glyph {
        Layout.fillHeight: true
        text: Theme.glyph.launcher
    }

    // Left opens the launcher, right opens it on its power rows (the "!"
    // mode). Both toggle, so a second click closes what the first opened.
    actions: ({
            [Qt.LeftButton]: () => Launcher.toggle(),
            [Qt.RightButton]: () => Launcher.openWith(Launcher.powerPrefix),
            [Qt.MiddleButton]: () => Launcher.toggle()
        })
}

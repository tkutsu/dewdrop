import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// The dimmed, blurred screen behind the launcher in its ! mode, so the rows
// read as the machine's off switch rather than one more search.
//
// A window of its own so the compositor can fade it: Hyprland blurs a layer
// all at once wherever its pixels pass the alpha floor, and only fades that
// blur along with the whole surface as it maps and unmaps. wrules.lua gives
// quickshell:veil blur and the "fade" animation; animation.lua's
// fadeLayersIn/Out set how long it takes.
//
// It also takes every click that misses the box: on the Top layer, under the
// launcher, over the bar and windows. A press here closes the launcher and
// goes no further.
PanelWindow {
    id: root

    WlrLayershell.namespace: "quickshell:veil"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.45
    }

    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: Launcher.hide()
    }
}

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.services

// The black behind the launcher's CRT exit (LauncherMenu.qml), held through
// session teardown or sleep until Power lets it go.
//
// A window of its own rather than a fill in the launcher's: Hyprland blurs
// whatever the launcher draws above 0.3 alpha, so a black fading in there
// would snap the whole desktop out of focus a third of the way through. The
// Top layer keeps it under the launcher box and over the bar and windows.
PanelWindow {
    id: root

    property bool completed: false

    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
    WlrLayershell.namespace: "quickshell:blackout"
    WlrLayershell.layer: WlrLayer.Top
    // The launcher has the keyboard until the command runs; then Escape here
    // is the way out of a black that has outstayed its command.
    WlrLayershell.keyboardFocus: Power.blackout ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Component.onCompleted: root.completed = true

    Rectangle {
        anchors.fill: parent
        color: "black"
        // From a first frame at zero, or the Behavior would not run.
        opacity: root.completed ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.fadeMs
                easing.type: Easing.InOutCubic
            }
        }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Power.blackout = false
    }
}

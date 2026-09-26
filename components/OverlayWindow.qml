import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs

// The screen-sized surface a launcher or a power menu is drawn on.
//
// Both want the same six things, and used to say all of them twice: a full-
// screen transparent layer so that clicking off the box dismisses it, exclusive
// keyboard focus for exactly as long as the box is wanted, and a first frame at
// zero so the reveal has somewhere to animate from.
//
// Drawn transparent on purpose: wrules.lua's layer rule ignores anything under
// 0.3 alpha, so only the box on top of this gets blurred and the rest of the
// screen is left alone. This is the part rofi could not do for itself — see
// services/Launcher.qml.
PanelWindow {
    id: root

    // Whether the box is wanted on screen. Not whether this window exists: the
    // box animates itself shut, so the surface outlives the intent by the
    // length of that (see qs.Linger).
    required property bool shown
    // The layer namespace, after "quickshell:". Needs a matching rule in
    // wrules.lua to be blurred.
    required property string name

    // Clicking anywhere that is not the box.
    signal dismissed

    // What the reveal animates off. It has to start false even though the box
    // is already wanted by the time the window exists — a Behavior does not run
    // on a property's first value, so without a frame at zero the box would
    // simply appear at full size.
    property bool completed: false
    readonly property bool opened: root.completed && root.shown

    Component.onCompleted: root.completed = true

    WlrLayershell.namespace: "quickshell:" + root.name
    WlrLayershell.layer: WlrLayer.Overlay
    // The box owns the keyboard while it is up, the way rofi did. Only while it
    // is up: holding the keyboard through the fold-away would eat the first
    // thing typed into whatever is underneath.
    WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Open where the user is, not wherever the compositor would have put it.
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    // Cover the strip the bar reserves as well, or the box centres itself in
    // what is left of the screen and sits low by half the bar's height.
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // Nothing on a box that is folding away is clickable, for the same reason
    // it no longer holds the keyboard: the click that dismissed it should not be
    // followed by a tenth of a second of presses disappearing into a surface
    // that is on its way out.
    mask: root.shown ? null : blank

    Region {
        id: blank
    }

    // Declared here rather than by the caller so it lands under everything the
    // caller adds: a base component's own children are created before the ones
    // appended at the instantiation site.
    MouseArea {
        anchors.fill: parent
        onClicked: root.dismissed()
    }
}

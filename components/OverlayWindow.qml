import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs

// The screen-sized surface a launcher or a power menu is drawn on.
//
// Both share a transparent drawing layer, keyboard focus while
// wanted, and a first frame at zero for the reveal. Only the menu accepts
// pointer input; Hyprland reports outside clicks without consuming them.
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
    // The menu's input area, excluding the fullscreen backdrop and shadows.
    required property Item inputItem

    // Clicking anywhere that is not the box.
    signal dismissed

    // What the reveal animates off. It has to start false even though the box
    // is already wanted by the time the window exists — a Behavior does not run
    // on a property's first value, so without a frame at zero the box would
    // simply appear at full size.
    property bool completed: false
    readonly property bool opened: root.completed && root.shown

    Component.onCompleted: {
        root.pickScreen();
        root.completed = true;
    }
    onShownChanged: if (root.shown) root.pickScreen()

    // Keep an open overlay on the screen selected when it was requested.
    function pickScreen(): void {
        root.screen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null;
    }

    WlrLayershell.namespace: "quickshell:" + root.name
    WlrLayershell.layer: WlrLayer.Overlay
    // Take keyboard input without blocking focus on an outside mouse press.
    // Release it during the fold-away so the next window can accept typing.
    WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

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
    mask: root.shown ? inputRegion : blank

    Region {
        id: inputRegion
        item: root.inputItem
    }

    Region {
        id: blank
    }

    HoverHandler {
        id: pointer
        parent: root.inputItem
        enabled: root.shown
    }

    // Match OpenPopup: outside presses dismiss and still reach their target.
    Connections {
        target: Hyprland
        enabled: root.shown

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "custom" && event.data === "click" && !pointer.hovered)
                root.dismissed();
        }
    }
}

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.src.core

// The screen-sized surface the launcher or the settings window is drawn on.
//
// Both share a transparent drawing layer, keyboard focus while
// wanted, a first frame at zero for the reveal, and a click outside the
// box closing it. Each menu chooses its input area.
//
// Drawn transparent on purpose: hypr/dewdrop.lua's layer rule ignores anything
// under 0.3 alpha, so only the box on top of this gets blurred and the rest of the
// screen is left alone. This is the part rofi could not do for itself — see
// services/Launcher.qml.
PanelWindow {
    id: root

    // Whether the box is wanted on screen. Not whether this window exists: the
    // box animates itself shut, so the surface outlives the intent by the
    // length of that (see qs.Linger).
    required property bool shown
    // The layer namespace, after "quickshell:". Needs a matching rule in
    // hypr/dewdrop.lua to be blurred.
    required property string name
    // The input area: the box the window draws.
    required property Item inputItem
    property Item dropdown: null

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
    onShownChanged: {
        outside.reset();
        if (root.shown) {
            root.clickedOut = false;
            root.pickScreen();
        }
    }

    // Keep an open overlay on the screen selected when it was requested.
    function pickScreen(): void {
        root.screen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null;
    }

    WlrLayershell.namespace: "quickshell:" + root.name
    WlrLayershell.layer: WlrLayer.Overlay
    // Keep the keyboard while up. On demand, a shortcut moving to a window or
    // a workspace took it, and so did the pointer under follow_mouse = 1, and
    // Escape went there. Release it during the fold-away so the next window can
    // accept typing.
    WlrLayershell.keyboardFocus: !root.shown ? WlrKeyboardFocus.None
        : root.renewing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive

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

    // A folding box takes no clicks, so its controls shouldn't say they would.
    Binding {
        target: root.inputItem
        property: "enabled"
        value: root.shown
    }

    Region {
        id: inputRegion
        item: root.inputItem
        Region { item: root.dropdown?.popup.visible ? root.dropdown.popup.contentItem.parent : null }
    }

    Region {
        id: blank
    }

    HoverHandler {
        id: pointer
        parent: root.inputItem
        enabled: root.shown
    }

    OutsideClick {
        id: outside
        // Qt reparents dropdown menus into its overlay, outside inputItem's
        // hover tree. Let an open menu handle its own selection and dismissal.
        enabled: root.shown && !root.inputItem.Controls.Overlay.overlay?.visible
        // A field's edit menu (TextMenu) is a popup window of its own.
        inside: pointer.hovered || PopupPointer.hovered > 0
        onReleased: Qt.callLater(() => {
            if (!root.shown)
                return;
            root.clickedOut = true;
            root.dismissed();
        })
    }

    // An exclusive layer has the click outside reach its window but hands the
    // keyboard back to the window before. So once the keyboard has gone, focus
    // what was clicked (dewdrop.lua's focus_under_cursor).
    property bool clickedOut: false

    // Hyprland still takes the keyboard from an exclusive layer when another
    // layer under the pointer unmaps (the launcher's ! veil), handing it to the
    // window there. Asking again wins it back, but only a request that changes
    // for a frame is acted on. A layer that wants the keyboard to itself (the
    // password panel, a hint overlay) keeps it until it closes.
    property bool renewing: false

    function reclaim(): void {
        if (root.shown && !root.inputItem.Window.window?.active && !claimed.running)
            claimed.running = true;
    }

    Connections {
        target: root.inputItem.Window.window
        function onActiveChanged() {
            if (root.inputItem.Window.window.active)
                return;
            if (root.clickedOut) {
                root.clickedOut = false;
                Hyprland.dispatch("focus_under_cursor()");
            }
            root.reclaim();
        }
    }

    Connections {
        target: Hyprland
        enabled: root.shown
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "closelayer")
                root.reclaim();
        }
    }

    Process {
        id: claimed
        command: ["hyprctl", "repl", `for _, l in ipairs(hl.get_layers()) do if l.mapped and l.keyboard_interactivity == 1 and l.namespace ~= "quickshell:${root.name}" then print("claimed") end end`]
        stdout: StdioCollector {
            id: claimedBy
        }
        onExited: if (root.shown && !claimedBy.text.includes("claimed")) {
            root.renewing = true;
            renew.restart();
        }
    }

    Timer {
        id: renew
        interval: 16
        onTriggered: root.renewing = false
    }
}

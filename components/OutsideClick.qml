import QtQuick
import Quickshell.Hyprland

// Observe a complete outside click without consuming the target application's input.
QtObject {
    id: root
    property bool enabled: true
    property bool inside: false
    property bool armed: false
    signal released

    function reset(): void { root.armed = false; }
    onEnabledChanged: root.reset()

    property Connections events: Connections {
        target: Hyprland
        enabled: root.enabled
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name !== "custom")
                return;
            if (event.data === "click")
                root.armed = !root.inside;
            else if (event.data === "click-release" && root.armed) {
                root.reset();
                root.released();
            }
        }
    }
}

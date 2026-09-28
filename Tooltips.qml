pragma Singleton

import QtQuick
import Quickshell

// Whether the bar's tooltips are warm. macOS makes you wait for the first
// one, and after that hands them over as fast as the pointer moves: once a
// tag is up, the next control's shows the moment it is reached, until the
// pointer has been off them all for a moment. Kept by components/HoverPopup.qml.
Singleton {
    id: root

    // How many are up: one, but two for the instant a handover overlaps.
    property int showing: 0
    readonly property bool warm: showing > 0 || cooling.running

    function shown(): void {
        root.showing++;
    }

    function hidden(): void {
        root.showing--;
        cooling.restart();
    }

    Timer {
        id: cooling
        // Enough to cross the gap between two modules, or a pill's end to
        // the next pill; not enough to leave the bar and come back.
        interval: 500
    }
}

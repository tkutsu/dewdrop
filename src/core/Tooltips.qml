pragma Singleton

import QtQuick
import Quickshell

// Whether the bar's tooltips are warm. The first one makes you wait, and
// after that they are handed over as fast as the pointer moves: once a
// tag is up, the next control's shows the moment it is reached, until the
// pointer has been off them all for a moment. Kept by components/HoverPopup.qml.
Singleton {
    id: root

    // How many are up: one, but two for the instant a handover overlaps.
    property int showing: 0
    readonly property bool warm: showing > 0 || cooling.running

    property var movingPills: []
    readonly property bool blocked: movingPills.length > 0

    // Track owners rather than a count so overlapping motion and teardown balance.
    function setMoving(pill: Item, moving: bool): void {
        const others = root.movingPills.filter(item => item !== pill);
        root.movingPills = moving ? [...others, pill] : others;
    }

    function shown(): void {
        root.showing++;
    }

    function hidden(): void {
        root.showing--;
        cooling.restart();
    }

    Timer {
        id: cooling
        // Enough to cross from one pill to the next, or to glance away and
        // come back; not enough to wander off and return cold.
        interval: 1000
    }
}

pragma Singleton

import QtQuick
import Quickshell

// Remembers what components/InkProbe.qml found, so an icon is measured once
// rather than once per time it appears.
//
// The bar sees the same handful of icons over and over: nm-applet walks up and
// down its signal strengths, Telegram swaps between quiet and attention, and a
// tray rebuild hands every delegate its icon again from scratch. Measuring
// costs a frame's worth of work — a grab off the GPU and a read back down — and
// none of it is worth paying twice for an answer that cannot have changed.
Singleton {
    id: root

    // Keyed by icon source. One number each, and only for icons the bar has
    // actually shown, so it stays the size of a tray rather than of a theme.
    property var known: ({})

    // A plain object does not tell anyone when it changes. Callers read this
    // on their way past, so a binding that asked before the answer arrived is
    // re-run once it has.
    property int revision: 0

    // 0 for anything not measured yet, which is the same thing a caller does
    // with a measurement that has not landed: draw at the asked size.
    function extentOf(source) {
        root.revision;
        return root.known[source] ?? 0;
    }

    function remember(source, extent) {
        root.known[source] = extent;
        root.revision++;
    }
}

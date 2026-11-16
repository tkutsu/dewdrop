import QtQuick
import qs.src.core
import qs.src.services

// When a popup's contents were last fetched, as the header button that
// fetches them again: "Updated 10:08", or the day once that was another one.
// A fetch that failed says so in the warning colour, still with the time of
// the last good one, so a list that stopped updating never passes for a fresh
// one. Opening the popup already fetches what is stale; this is the retry.
PopupButton {
    id: root

    // The last good fetch, in seconds since the epoch; 0 for none yet.
    property double at: 0
    property bool failed: false

    readonly property string when: {
        if (!root.at)
            return "";
        const then = new Date(root.at * 1000);
        return then.toDateString() === new Date(WallClock.now).toDateString() ? Qt.formatTime(then, "HH:mm") : Qt.formatDate(then, "d MMM");
    }

    framed: true
    glyph: Theme.glyph.refresh
    warn: root.failed
    label: root.failed ? (root.when ? `Couldn't Update · ${root.when}` : "Couldn't Update") : root.when ? `Updated ${root.when}` : "Refresh"
    name: root.when ? `Refresh, ${root.failed ? "couldn't update since" : "updated"} ${root.when}` : "Refresh"
}

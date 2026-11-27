import QtQuick
import qs.src.core
import qs.src.services

// When a popup's contents were last fetched, as the header button that
// fetches them again: the time, "10:08", beside the refresh glyph that says
// what pressing it does, or the day once that was another one.
// A fetch that failed says so with the warning mark and colour, still with the
// time of the last good one, so a list that stopped updating never passes for
// a fresh one, and the button keeps its width in a header with no room to
// spare. The arrows go round once whenever a fetch is asked for, from a press
// or from the popup opening, so asking always shows; a check mark answers a
// press once that fetch lands.
//
// Opening the popup fetches what is older than `staleAfter`, unless the last
// try failed: that one waits on its service's back-off, or on a press here.
//
// A `service` supplies it all (`updatedAt`, `loading`, `refresh`, and
// `retryable` with `retryNow` where it backs off); anything else sets `at`,
// `busy`, `failed` and `fetch` itself (the weather).
PopupButton {
    id: root

    property var service: null
    // The last good fetch, in seconds since the epoch; 0 for none yet.
    property double at: root.service?.updatedAt ?? 0
    property bool busy: !!root.service?.loading
    property bool failed: !root.service ? false : root.service.retryable !== undefined ? root.service.retryable : root.service.trouble !== ""
    property var fetch: () => root.failed && root.service?.retryNow ? root.service.retryNow() : root.service?.refresh()
    property int staleAfter: 5 * 60

    property bool asked: false

    function ask(): void {
        root.spin();
        root.fetch();
    }

    readonly property string when: {
        if (!root.at)
            return "";
        const then = new Date(root.at * 1000);
        return then.toDateString() === new Date(WallClock.now).toDateString() ? Settings.sayTime(then) : Qt.formatDate(then, "d MMM");
    }

    framed: true
    glyph: root.failed ? Theme.glyph.warning : Theme.glyph.refresh
    warn: root.failed
    label: root.when || (root.failed ? "Couldn't Update" : "Refresh")
    name: root.when ? `Refresh, ${root.failed ? "couldn't update since" : "updated"} ${root.when}` : "Refresh"

    onTapped: {
        root.asked = true;
        root.ask();
    }
    onBusyChanged: if (!root.busy && root.asked) {
        root.asked = false;
        if (!root.failed)
            root.confirm();
    }
    Component.onCompleted: if (root.live && !root.busy && !root.failed && root.at > 0 && Date.now() / 1000 - root.at > root.staleAfter)
        root.ask()
}

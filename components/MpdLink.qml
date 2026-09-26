import QtQuick
import Quickshell
import Quickshell.Io

// One connection to mpd that comes back on its own, for services/Mpd.qml,
// which keeps two of them (one parked in `idle`, one for commands).
//
// The connection is rebuilt rather than re-dialled. A Socket whose *first*
// connect fails is dead for good in Quickshell 0.3.1: `connected` never
// changes, so nothing hears about the failure, and neither assigning
// `connected = true` again nor reassigning `path` makes it try a second time
// — measured against this build, not assumed. A drop from a connection that
// did come up does re-dial, but the two arrive together whenever mpd is
// stopped rather than merely absent, so both go the same way: throw the
// object away and build another.
//
// `connected` is read off the socket rather than set by its signal: a fresh
// socket is already open by the time a handler on it would be attached, so
// the first change never arrives. Reading through the Loader's `item`, which
// is set once the socket is finished, is what turns that into a change.
Item {
    id: root

    required property string path

    readonly property bool connected: loader.item ? loader.item.connected : false

    // One line of the reply, without its newline.
    signal line(string text)

    function write(text): void {
        if (loader.item)
            loader.item.write(text);
    }

    // Try again now rather than at the end of the current wait: for the
    // moment someone types a command into a link that has settled into its
    // slow retry. Not more than once per short interval, so a burst of
    // keypresses at a stopped mpd is one dial rather than one each.
    function wake(): void {
        if (root.connected || Date.now() - root.lastTry < 5000)
            return;
        root.redial();
        retry.restart();
    }

    // For when mpd is known to have just come up: dial at once, and go back to
    // the quick retries whatever the wait had grown to.
    function dialNow(): void {
        if (root.connected)
            return;
        root.tries = 0;
        root.redial();
        retry.restart();
    }

    property int tries: 0
    property real lastTry: 0

    function redial(): void {
        root.tries++;
        root.lastTry = Date.now();
        loader.active = false;
        loader.active = true;
    }

    Loader {
        id: loader

        sourceComponent: Component {
            Socket {
                path: root.path
                connected: true

                parser: SplitParser {
                    onRead: line => root.line(line)
                }
            }
        }
    }

    onConnectedChanged: if (root.connected)
        root.tries = 0

    // Quick for the first half minute, then patient. mpd is normally either
    // up or stopped for the evening; a dial every five seconds for the
    // second case is a ConnectionRefused in the log by the thousand and a
    // socket built and torn down for nothing all night.
    Timer {
        id: retry
        interval: root.tries < 6 ? 5000 : 45000
        repeat: true
        running: !root.connected
        onTriggered: root.redial()
    }
}

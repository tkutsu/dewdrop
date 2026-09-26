pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Unread Gmail count. unread-count speaks IMAP over TLS and is not something
// worth rewriting in QML, but the 30s loop and the display rules that
// taskbar-email.sh wrapped around it live here now.
Singleton {
    id: root

    property int count: 0
    property bool loaded: false
    property string detail: "Connecting…"

    readonly property string icon: count > 0 ? Theme.glyph.mailUnread : Theme.glyph.mailRead
    readonly property string label: !loaded || count === 0 ? "" : String(Math.min(count, 99))
    readonly property string tooltip: loaded ? detail : "Connecting…"

    // The 30s loop is usually soon enough; this is for the moment you are
    // waiting on a mail and do not want to watch the clock.
    function refresh() {
        if (!poll.running)
            poll.running = true;
    }

    Process {
        id: poll
        running: true
        // Bounded, because this is a TLS round trip to someone else's server
        // and `refresh()` only ever starts a run that is not already going. A
        // connection left hanging — which is what a resume onto a network that
        // is not back yet gives you — would therefore be the last one of the
        // session: the 30s timer would find it still running and skip, every
        // time, for as long as the bar is up. 25 seconds is well past the
        // second or so a real answer takes.
        command: ["timeout", "25", Quickshell.env("HOME") + "/_scripts/unread-count", "-S", "imap.gmail.com:993"]

        stdout: StdioCollector {
            onStreamFinished: {
                let state;
                try {
                    state = JSON.parse(text);
                } catch (e) {
                    return;
                }
                root.count = parseInt(state.text) || 0;
                root.detail = state.tooltip ?? "";
                root.loaded = true;
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}

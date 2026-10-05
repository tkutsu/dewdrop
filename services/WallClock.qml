pragma Singleton

import QtQuick
import Quickshell

// One wall-clock check for services whose Qt countdowns pause during suspend.
Singleton {
    id: root

    property double now: Date.now()
    signal wokeUp

    // Clock corrections also invalidate cached dates and elapsed countdowns.
    function sample(at: double): void {
        const elapsed = at - root.now;
        root.now = at;
        if (elapsed > 90000 || elapsed < -10000)
            root.wokeUp();
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.sample(Date.now())
    }
}

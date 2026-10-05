pragma Singleton

import QtQuick
import Quickshell

// One wall-clock check for services whose Qt countdowns pause during suspend.
Singleton {
    id: root

    property double now: Date.now()
    signal wokeUp

    // Clock corrections also invalidate cached dates and elapsed countdowns.
    // Every five seconds, so a wake is noticed within that rather than a
    // minute later, with the bar clock still on the time it went to sleep at.
    // Three ticks' worth of gap is a wake; one late tick is not.
    function sample(at: double): void {
        const elapsed = at - root.now;
        root.now = at;
        if (elapsed > 15000 || elapsed < -10000)
            root.wokeUp();
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: root.sample(Date.now())
    }
}

pragma Singleton

import QtQuick
import Quickshell
import qs

// The bar's main Google sign-in, shared by Tasks, Agenda and Email. The
// sign-in itself is GoogleAccount.qml.
//
// ~/_scripts/gtasks-setup walks the consent once and leaves a refresh token in
// gtasks.json, granted for every scope these services use; scripts/gtasks-auth
// is the consent step on its own, which the popups run to reconnect.
GoogleAccount {
    id: root

    file: "gtasks.json"
    // calendar.app.created cannot write the primary calendar and returns 404,
    // not a scope error, so a token without one of these is sent back.
    requireAny: ["calendar", "calendar.events", "calendar.events.owned"]

    // The one-time sign-in, as the messages name it for you to go and run.
    readonly property string setup: Paths.script("gtasks-setup").replace(Settings.home, "~")

    // --- days ----------------------------------------------------------------
    // Google's APIs speak in calendar days, and both services compare them as
    // ISO strings: they sort lexicographically, so "before today" is just "<".
    function dayString(date: var): string {
        const pad = n => n < 10 ? "0" + n : String(n);
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    }

    // Minute ticks catch midnight within a minute of waking from suspend.
    readonly property date now: clock.date
    readonly property string today: root.dayString(clock.date)

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Re-read at once after a wake, as the bar clock is (see Clock.qml).
    Connections {
        target: WallClock

        function onWokeUp(): void {
            clock.enabled = false;
            clock.enabled = true;
        }
    }
}

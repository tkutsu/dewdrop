import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// The timer pill: what is counting down, and what it is counting down to.
//
// An island of its own beside the music pill rather than a glyph on the right
// one, for the same reason the player is: its label changes every second, and
// nothing that only changes when something happens should have to move over for
// that. With nothing set there is no pill at all.
//
// It carries whichever timer is nearest its end, the next alarm when nothing is
// running, and the fact that something has gone off when something has. Those
// are three states of one thing, so they are one pill and not three modules.
BarItem {
    id: root

    // For the pill around it, which is this module and nothing else and so
    // slides under the clock with it once nothing is set: the bar places the
    // pill off `reveal` (see Bar.qml), and nothing folds.
    stowed: !Timers.loaded
    folds: false
    readonly property real progress: Timers.progress

    readonly property bool ringing: Timers.ringing.length > 0

    // What the pill shows, kept while the pill goes: the timer is gone before
    // its pill is under the clock, and the glyph and figures would otherwise
    // swap to "nothing set" halfway there. Bound only while something is set
    // and left holding the last value after (same as Music and Notice).
    property string shownGlyph: ""
    property string shownLabel: ""

    Binding {
        root.shownGlyph: Timers.glyph
        root.shownLabel: Timers.label
        when: Timers.loaded
        restoreMode: Binding.RestoreNone
    }

    spacing: Theme.mediaGap
    popup: TimerPopup {}

    Glyph {
        Layout.fillHeight: true
        text: root.shownGlyph
        fontSize: Theme.glyphSizeLarge
        // White even while ringing: the hop below on the alarm's beat is the
        // signal, and orange means "warm" everywhere else on this bar.
        color: Theme.fg

        transform: Translate { y: bounce.offset }
    }

    // On the beat, not beside it: the alarm sounds on Timers.beatMs and the
    // glyph hops once per sound, so the two read as one thing going off.
    Bounce {
        id: bounce
        running: root.ringing
        periodMs: Timers.beatMs
    }

    BarText {
        Layout.fillHeight: true
        text: root.shownLabel
        // A paused timer is the label gone quiet, the same way a paused song
        // is — the glyph beside it already says which of the two it is, and a
        // second mark saying so again would be the loudest thing in the pill.
        opacity: root.ringing || (Timers.focus && Timers.focus.running) || !Timers.focus ? 1 : Theme.dimOpacity

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.fadeMs
            }
        }
    }

    // Left is the thing you came to do: shut it up if it is shouting, hold it
    // if it is running, and otherwise set one. Right is the second thought —
    // five more minutes, or a new timer when there is nothing to snooze.
    // Middle throws away, which is the one action here that cannot be undone
    // and so is the one nothing lands on by accident.
    onClicked: function (mouse) {
        if (mouse.button === Qt.LeftButton) {
            if (root.ringing)
                Timers.hush();
            else if (Timers.focus)
                Timers.toggle(Timers.focus.id);
            else
                Launcher.openWith(Launcher.timerPrefix);
        } else if (mouse.button === Qt.RightButton) {
            if (root.ringing)
                Timers.snooze(5);
            else
                Launcher.openWith(Launcher.timerPrefix);
        } else if (mouse.button === Qt.MiddleButton) {
            if (root.ringing)
                Timers.hush();
            else if (Timers.focus)
                Timers.cancel(Timers.focus.id);
        }
    }

    // A minute a notch, on whichever timer the pill is showing. The commonest
    // correction to a timer is that it was set a bit short, and this is the one
    // gesture that does not involve opening anything.
    onScrollUp: if (Timers.focus)
        Timers.bump(Timers.focus.id, 60000)
    onScrollDown: if (Timers.focus)
        Timers.bump(Timers.focus.id, -60000)
}

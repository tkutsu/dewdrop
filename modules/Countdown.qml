import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// The timer pill: what is counting down, and what it is counting down to.
//
// An pill of its own beside the music pill rather than a glyph on the right
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
    // is drawn into the clock with it once nothing is set: the bar draws the
    // pill off `reveal` (see Bar.drop), and nothing folds.
    stowed: !Timers.loaded
    folds: false

    // And the popup goes with it: the last timer cancelled from the popup's
    // own row would otherwise leave it hanging from a pill that is no longer
    // there.
    onStowedChanged: if (stowed)
        OpenPopup.close(root)
    readonly property real progress: Timers.progress
    // How fast that runs while the timer does, for the pill to carry the line
    // on between the ticks (Pill.rate). `total` is in milliseconds.
    readonly property real rate: !ringing && Timers.focus?.running && Timers.focus.total > 0 ? 1000 / Timers.focus.total : 0

    readonly property bool ringing: Timers.ringing.length > 0

    // What the pill shows, kept while the pill goes: the timer is gone before
    // its pill is, and the glyph and figures would otherwise swap to "nothing
    // set" halfway there. Bound only while something is set
    // and left holding the last value after (same as Music and Notice).
    //
    // Copied a tick after any of them changes rather than bound: all three
    // come off the same timer going, and a Binding gated on `loaded` could
    // hear the glyph and label go to "nothing set" before `loaded` did, which
    // snapped the pill to a bare glyph as it started to leave. By the next
    // tick they agree.
    property string shownGlyph: ""
    property string shownLabel: ""

    function sync() {
        if (!Timers.loaded)
            return;
        root.shownGlyph = Timers.glyph;
        root.shownLabel = Timers.label;
    }

    Connections {
        target: Timers

        function onGlyphChanged() {
            Qt.callLater(root.sync);
        }
        function onLabelChanged() {
            Qt.callLater(root.sync);
        }
        function onLoadedChanged() {
            Qt.callLater(root.sync);
        }
    }

    Component.onCompleted: root.sync()

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

    // The time left rolls from one second to the next (RollingText); a timer
    // that has gone off shows its name instead, which is words and is drawn
    // whole.
    Item {
        readonly property bool figures: /^[0-9:]+$/.test(root.shownLabel)

        Layout.fillHeight: true
        implicitWidth: figures ? rolling.implicitWidth : words.implicitWidth
        // A paused timer is the label gone quiet, the same way a paused song
        // is — the glyph beside it already says which of the two it is, and a
        // second mark saying so again would be the loudest thing in the pill.
        opacity: root.ringing || (Timers.focus && Timers.focus.running) || !Timers.focus ? 1 : Theme.dimOpacity

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.fadeMs
            }
        }

        BarText {
            id: words
            height: parent.height
            visible: !parent.figures
            text: root.shownLabel
        }

        RollingText {
            id: rolling
            height: parent.height
            visible: parent.figures
            text: parent.figures ? root.shownLabel : ""
            countsDown: true
        }
    }

    // Left is the popup (BarItem.popupButton). Right is the thing you came to
    // do: shut it up if it is shouting, hold it if it is running, and
    // otherwise set one. Middle shuts it up too and otherwise throws away,
    // which is the one action here that cannot be undone and so is the one
    // nothing lands on by accident.
    actions: ({
            [Qt.RightButton]: () => {
                if (root.ringing)
                    Timers.hush();
                else if (Timers.focus)
                    Timers.toggle(Timers.focus.id);
                else
                    Launcher.openWith(Launcher.taskPrefix);
            },
            // Nothing to throw away with no timer running or ringing.
            [Qt.MiddleButton]: root.ringing || Timers.focus ? () => {
                if (root.ringing)
                    Timers.hush();
                else
                    Timers.cancel(Timers.focus.id);
            } : null
        })

    // A minute a notch, on whichever timer the pill is showing. The commonest
    // correction to a timer is that it was set a bit short, and this is the one
    // gesture that does not involve opening anything.
    onScrollUp: if (Timers.focus)
        Timers.bump(Timers.focus.id, 60000)
    onScrollDown: if (Timers.focus)
        Timers.bump(Timers.focus.id, -60000)
}

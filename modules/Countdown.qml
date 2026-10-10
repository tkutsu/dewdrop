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
//
// No popup: pointed at, it opens out the way the music pill does. The glyph
// gives its place to a close mark, and the timer's name and a pause or play
// hand fold out after the label, so what can be done to the timer is on the
// timer. The full list, and
// the phone settings, are the clock's popup.
BarItem {
    id: root
    name: "Dismiss ringing timer"

    // For the pill around it, which is this module and nothing else and so
    // is drawn into the clock with it once nothing is set: the bar draws the
    // pill off `reveal` (see Bar.drop), and nothing folds.
    stowed: !Timers.loaded
    folds: false

    // Whether a hover is run rather than set: only for a pill at rest (see
    // Music.settled).
    readonly property bool settled: reveal >= 1

    readonly property real progress: Timers.progress
    // How fast that runs while the timer does, for the pill to carry the line
    // on between the ticks (Pill.rate). `total` is in milliseconds.
    readonly property real rate: !ringing && Timers.focus?.running && Timers.focus.total > 0 ? 1000 / Timers.focus.total : 0

    readonly property bool ringing: Timers.ringing.length > 0

    // What the hands act on: the timer the pill shows, or the alarm it shows
    // when no timer is set. Pausing an alarm is switching it off, the same as
    // the popup's button always was.
    readonly property var target: Timers.focus ?? Timers.nextAlarm

    // Ringing, the hands stand down and a click anywhere hushes (`actions`).
    function hold() {
        if (root.target)
            Timers.toggle(root.target.id);
    }

    function dismiss() {
        if (root.target)
            Timers.cancel(root.target.id);
    }

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
    // The name, for the hover. Not while ringing, where the label already is
    // the name.
    property string shownName: ""

    function sync() {
        if (!Timers.loaded)
            return;
        root.shownGlyph = Timers.glyph;
        root.shownLabel = Timers.label;
        root.shownName = root.ringing ? "" : root.target?.label ?? "";
    }

    onTargetChanged: Qt.callLater(root.sync)

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

    // Each part brings its own gap, so that the pause hand can take its gap
    // with it as it folds.
    spacing: 0
    // While ringing, the whole pill is one dismissal target.
    dips: root.ringing
    contentAnimating: nameWidth.running || holdWidth.running

    // Out only while the pill is pointed at.
    readonly property bool handsOut: root.containsMouse

    // The glyph's slot, and the close button once the hands are out: the
    // glyph fades to what pressing it will do, as the music pill's sleeve
    // does. Ringing, it keeps hopping and a press shuts it up. Wide enough
    // for either, so the swap moves nothing.
    Item {
        id: slot
        readonly property bool inkHovered: slotHover.hovered

        HoverHandler { id: slotHover }

        readonly property bool marked: root.handsOut && !root.ringing

        Layout.fillHeight: true
        implicitWidth: Math.max(glyph.implicitWidth, mark.implicitWidth) + Theme.mediaGap
        transform: Translate { y: slotTap.pressed ? Theme.pressDip : 0 }

        Accessible.role: Accessible.Button
        Accessible.name: "Cancel timer"
        Accessible.onPressAction: if (slotTap.enabled && enabled && visible)
            root.dismiss()

        TapHandler {
            id: slotTap
            enabled: !root.ringing
            margin: Theme.pressDip
            onTapped: root.dismiss()
        }

        Glyph {
            id: glyph
            x: Math.round((slot.width - Theme.mediaGap - width) / 2)
            height: parent.height
            text: root.shownGlyph
            fontSize: Theme.glyphSizeLarge
            // White even while ringing: the hop below on the alarm's beat is the
            // signal, and orange means "warm" everywhere else on this bar.
            color: Theme.fg
            opacity: slot.marked ? 0 : 1

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.fadeMs
                }
            }

            transform: Translate { y: bounce.offset }
        }

        Glyph {
            id: mark
            x: Math.round((slot.width - Theme.mediaGap - width) / 2)
            height: parent.height
            text: Theme.glyph.close
            opacity: slot.marked ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.fadeMs
                }
            }
        }
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

    // The name, folding out with the hands: the countdown says how long, this
    // says what for. Secondary, since it is read after the figures. A timer
    // with no name has nothing to fold out.
    Item {
        readonly property real full: Theme.mediaGap + name.implicitWidth

        Layout.fillHeight: true
        implicitWidth: root.handsOut && root.shownName !== "" ? full : 0
        clip: width < full
        opacity: full > 0 ? width / full : 0
        transform: Translate { y: nameTap.pressed ? Theme.pressDip : 0 }

        Behavior on implicitWidth {
            enabled: root.settled
            NumberAnimation {
                id: nameWidth
                duration: Theme.foldMs
                easing.type: Easing.InOutCubic
            }
        }

        BarText {
            id: name
            x: Theme.mediaGap
            height: parent.height
            text: root.shownName
            color: Theme.label2
            maxWidth: Theme.mediaTitleWidth

            // A second way to the pause beside it, so it is left out of the
            // accessibility tree: one target there per action.
            TapHandler {
                id: nameTap
                enabled: !root.ringing && root.handsOut && root.shownName !== ""
                onTapped: root.hold()
            }
        }
    }

    // The pause hand belongs to a pending timer, never a finished one.
    Item {
        readonly property real full: Theme.mediaGap + hold.implicitWidth

        Layout.fillHeight: true
        visible: !root.ringing
        implicitWidth: root.handsOut ? full : 0
        clip: width < full
        opacity: width / full

        Behavior on implicitWidth {
            enabled: root.settled
            NumberAnimation {
                id: holdWidth
                duration: Theme.foldMs
                easing.type: Easing.InOutCubic
            }
        }

        Glyph {
            id: hold
            readonly property bool inkHovered: holdHover.hovered

            HoverHandler { id: holdHover; enabled: root.handsOut }

            x: Theme.mediaGap
            height: parent.height
            text: root.target?.running ? Theme.glyph.paused : Theme.glyph.playing
            transform: Translate { y: holdTap.pressed ? Theme.pressDip : 0 }

            Accessible.role: Accessible.Button
            Accessible.name: root.target?.running ? "Pause timer" : "Resume timer"
            Accessible.onPressAction: if (holdTap.enabled && enabled && visible)
                root.hold()

            TapHandler {
                id: holdTap
                enabled: root.handsOut
                margin: Theme.pressDip
                onTapped: root.hold()
            }
        }
    }

    // Right is the thing you came to do: shut it up if it is shouting, hold it
    // if it is running, and otherwise set one. Middle shuts it up too and
    // otherwise throws away, the close hand without reaching for it.
    actions: ({
            [Qt.LeftButton]: root.ringing ? () => Timers.hush() : null,
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
    scrolls: true
    Accessible.onScrollUpAction: scrollUp()
    Accessible.onScrollDownAction: scrollDown()
    onScrollUp: if (Timers.focus)
        Timers.bump(Timers.focus.id, 60000)
    onScrollDown: if (Timers.focus)
        Timers.bump(Timers.focus.id, -60000)
}

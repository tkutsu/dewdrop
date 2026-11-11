import QtQuick
import QtQuick.Layouts
import qs.src.core
import qs.src.components
import qs.src.services

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
// Hover reveals the name and a cancel button on the right. The icon and a
// right click fold it into the centre pill; the label opens the full list.
BarItem {
    id: root
    name: root.ringing ? "Dismiss ringing timer" : "Timers"

    property bool dismissed: false
    function collapse() {
        root.dismissed = true;
        OpenPopup.close(root);
    }
    function expand() {
        root.dismissed = false;
    }
    onRingingChanged: if (ringing)
        root.expand()

    // For the pill around it, which is this module and nothing else and so
    // is drawn into the clock with it once nothing is set: the bar draws the
    // pill off `reveal` (see Bar.drop), and nothing folds.
    stowed: (root.dismissed || !Timers.loaded) && !exitHeld
    folds: false

    popup: TimerPopup {
        morphs: true
    }
    // The label opens it (below), not the whole pill: the hands either side
    // of it are buttons of their own.
    popupButton: Qt.NoButton

    // Whether a hover is run rather than set: only for a pill at rest (see
    // Music.settled).
    readonly property bool settled: reveal >= 1
    readonly property bool sliding: root.pill?.slidesContent ?? false
    readonly property real glassWidth: sliding ? pill.foldBox.z : width
    readonly property real glassLeft: sliding ? pill.foldBox.x : 0
    readonly property real iconInset: sliding ? Math.min(padLeft,
        Math.max(0, (glassWidth - glyph.width) / 2)) : 0
    readonly property real titleLoss: sliding ? Math.max(0, pill.width - glassWidth) : 0
    property Item mergedIcon: null
    readonly property MediaIconHandoff iconHandoff: MediaIconHandoff {
        source: glyph
        target: root.mergedIcon
        reveal: root.sliding && root.pill.bounceBeforeCollapse ? root.pill.dropReveal : root.reveal
        restingX: root.sliding ? root.glassLeft + root.iconInset - root.padLeft : 0
    }
    readonly property bool iconInCentre: root.mergedIcon !== null && iconHandoff.progress > 0

    readonly property real progress: Timers.progress
    // Carry the line between ticks, over the countdown or the alarm's last hour.
    readonly property real rate: {
        if (root.ringing || root.progress < 0)
            return 0;
        if (Timers.focus)
            return Timers.focus.running ? 1000 / Timers.focus.total : 0;
        return 1000 / Timers.alarmTrackMs;
    }

    readonly property bool ringing: Timers.ringing.length > 0
    readonly property int runningCount: Timers.entries.filter(e => e.running && !Timers.ringing.some(r => r.id === e.id)).length + Timers.ringing.length

    // Cancel the displayed timer or alarm; ringing has its own dismissal.
    readonly property var target: Timers.focus ?? Timers.nextAlarm

    function dismiss() {
        if (root.ringing)
            Timers.hush();
        else if (root.target)
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
    property var shownSmallRanges: []
    // The name, for the hover. Not while ringing, where the label already is
    // the name.
    property string shownName: ""

    function sync() {
        if (!Timers.loaded)
            return;
        root.shownGlyph = Timers.glyph;
        root.shownLabel = Timers.label;
        const alarm = root.ringing ? Timers.ringing[0] : !Timers.focus ? Timers.nextAlarm : null;
        root.shownSmallRanges = alarm?.kind === "alarm" && (!root.ringing || alarm.label === "")
            ? Timers.alarmDisplay(alarm.hour, alarm.minute).smallRanges : [];
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
            if (!Timers.loaded)
                root.dismissed = false;
            Qt.callLater(root.sync);
        }
    }

    Component.onCompleted: root.sync()

    // The name and cancel button take their gaps with them as they fold.
    spacing: 0
    // While ringing, the whole pill is one dismissal target.
    dips: root.ringing
    textPress: true
    contentAnimating: nameWidth.running || cancelWidth.running

    // Out only while the pill is pointed at.
    readonly property bool handsOut: root.settled && root.containsMouse

    // The icon returns the running timer to its central slot.
    Item {
        id: slot
        readonly property bool inkLit: true
        Layout.fillHeight: true
        implicitWidth: glyph.implicitWidth + Theme.mediaGap
        scale: slotPress.scale
        transform: Translate { x: root.iconHandoff.sourceX }
        opacity: (root.mergedIcon ? 1 - root.iconHandoff.progress : 1)
            * (root.sliding && !root.mergedIcon ? root.pill.iconOpacity : 1)

        PressGlass {
            id: slotPress
            icon: slot
            area: slotTap
        }
        ClickArea {
            id: slotTap
            anchors.fill: parent
            enabled: root.settled && !root.stowed
            acceptedButtons: Qt.LeftButton
            name: "Collapse timers"
            Accessible.ignored: !enabled
            actions: ({ [Qt.LeftButton]: root.collapse })
        }
        BadgedGlyph {
            id: glyph
            scale: root.sliding ? root.pill.iconScale : 1
            x: Math.round((slot.width - Theme.mediaGap - width) / 2)
            height: parent.height
            glyph: root.shownGlyph
            glyphSize: Theme.glyphSizeLarge
            badge: root.runningCount > 0 && Settings.badgeStyle("countdown") !== "hide" ? String(root.runningCount) : ""
            dot: Settings.badgeStyle("countdown") === "dot"
            underdot: Settings.badgeStyle("countdown") === "underdot"
            transform: Translate { y: bounce.offset }
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
    // whole. And the popup's button, which presses in by itself; ringing, a
    // click anywhere hushes instead (`actions`).
    Item {
        id: labelBox
        readonly property bool figures: /^[0-9:]+$/.test(root.shownLabel) || root.shownSmallRanges.length > 0

        Layout.fillHeight: true
        implicitWidth: figures ? rolling.implicitWidth : words.implicitWidth
        scale: labelPress.scale
        transform: Translate { x: root.sliding ? root.glassLeft + root.iconInset - root.padLeft : 0 }

        PressGlass {
            id: labelPress
            icon: labelBox
            area: labelTap
            textPress: true
        }

        // A label named by the time it shows, as ClickArea's `shows`.
        Accessible.role: Accessible.StaticText
        Accessible.name: root.shownLabel || "Timers"
        Accessible.description: "Timers"
        Accessible.onPressAction: if (labelTap.enabled && enabled && visible)
            root.togglePopup()

        TapHandler {
            id: labelTap
            enabled: !root.ringing
            // Keep the top screen pixel inside the target as it shrinks.
            margin: Theme.barInset
            // On the press, as a bar item's popup opens (ClickArea.eagerButtons).
            onPressedChanged: if (pressed)
                root.togglePopup()
        }

        // With another module's popup up, resting on the label opens this
        // one in its place, as the music pill's title does.
        HoverHandler {
            onHoveredChanged: OpenPopup.browse(root, hovered)
        }
        // A paused timer is the label gone quiet, the same way a paused song
        // is — the glyph beside it already says which of the two it is, and a
        // second mark saying so again would be the loudest thing in the pill.
        opacity: root.ringing || (Timers.focus && Timers.focus.running) || !Timers.focus ? 1 : Theme.dimOpacity

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.fadeMs
            }
        }

        Marquee {
            id: labelText
            width: Math.max(0, Math.min(labelBox.width - root.titleLoss,
                labelBox.width * (root.sliding ? root.pill.textReveal : 1)))
            height: parent.height
            contentWidth: labelBox.implicitWidth
            active: true
            paused: true
            travel: root.titleLoss

            BarText {
                id: words
                height: parent.height
                visible: !labelBox.figures
                text: root.shownLabel
            }

            RollingText {
                id: rolling
                height: parent.height
                visible: labelBox.figures
                text: labelBox.figures ? root.shownLabel : ""
                smallRanges: root.shownSmallRanges
                countsDown: !!Timers.focus
            }
        }
    }

    // The name, folding out with the hands: the countdown says how long, this
    // says what for. Secondary, since it is read after the figures. A timer
    // with no name has nothing to fold out.
    Item {
        id: nameBox
        readonly property real full: Theme.mediaGap + name.implicitWidth

        Layout.fillHeight: true
        implicitWidth: root.handsOut && root.shownName !== "" ? full : 0
        clip: width < full
        opacity: full > 0 ? width / full : 0
        scale: namePress.scale

        PressGlass {
            id: namePress
            icon: nameBox
            area: nameTap
            textPress: true
        }

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

            // The name opens the same timer list as the figures.
            TapHandler {
                id: nameTap
                enabled: !root.ringing && root.handsOut && root.shownName !== ""
                onTapped: root.togglePopup()
            }
        }
    }

    // Cancellation stays at the far right and is available only while revealed.
    Item {
        id: cancelBox
        readonly property real full: Theme.mediaGap + mark.implicitWidth
        Layout.fillHeight: true
        implicitWidth: root.handsOut ? full : 0
        clip: width < full
        opacity: width / full

        Behavior on implicitWidth {
            enabled: root.settled
            NumberAnimation {
                id: cancelWidth
                duration: Theme.foldMs
                easing.type: Easing.InOutCubic
            }
        }
        Glyph {
            id: mark
            readonly property bool inkLit: true
            x: Theme.mediaGap
            height: parent.height
            text: Theme.glyph.close
            scale: cancelPress.scale

            PressGlass {
                id: cancelPress
                icon: mark
                area: cancelTap
            }
            ClickArea {
                id: cancelTap
                anchors.fill: parent
                enabled: root.handsOut && !root.stowed && (root.ringing || root.target !== null)
                acceptedButtons: Qt.LeftButton
                name: root.ringing ? "Dismiss ringing timer" : "Cancel timer"
                Accessible.ignored: !enabled || cancelBox.opacity <= 0
                actions: ({ [Qt.LeftButton]: root.dismiss })
            }
        }
    }

    // Right folds the pill without changing its timer. Middle retains quick cancellation.
    actions: ({
            [Qt.LeftButton]: root.ringing ? () => Timers.hush() : null,
            [Qt.RightButton]: root.collapse,
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

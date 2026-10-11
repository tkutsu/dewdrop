import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// The music pill: what is playing, and when pointed at, a hand either side of
// it. The title opens the popup — it is the widest thing in the pill and the
// one you are already looking at, so it is also the cheapest to hit. The
// glyph beside it is play/pause, and so is a right click anywhere on the pill.
//
// The four left targets are TapHandlers rather than the BarItem's own click,
// which only has the right button here: one module, four targets, and a
// handler on the item that draws each one is what keeps them from having to be
// told apart by pointer position.
BarItem {
    id: root

    // For the pill around it, which is this module and nothing else and so
    // is drawn into its neighbour with it when there is nothing to play: the
    // bar draws the pill off `reveal` (see Bar.drop), and nothing folds.
    stowed: !Mpd.loaded
    folds: false

    // And the popup goes with it: mpd put down from the popup's own quit
    // button, or the queue emptied, would otherwise leave it hanging from a
    // pill that is no longer there.
    onStowedChanged: if (stowed)
        OpenPopup.close(root)

    // Whether a change is run rather than set: only for a pill at rest. One
    // arriving or leaving is drawn off its width at rest (see Bar.drop), and
    // its contents are hidden anyway.
    readonly property bool settled: reveal >= 1

    // And for the outline it draws: how far through the track we are. Held
    // like the title below, so the line fades with the pill rather than
    // dropping out the moment the queue empties.
    property real progress: 0
    readonly property real position: Mpd.duration > 0 ? Mpd.elapsed / Mpd.duration : 0
    // How fast that runs while playing, for the pill to carry the line on
    // between mpd's seconds (Pill.rate).
    readonly property real rate: Mpd.state === "play" && Mpd.duration > 0 ? 1 / Mpd.duration : 0

    // Forward a second at a time is set, not run (Pill.lit says why). Back —
    // a new track, prev, a seek — the line winds back round to where it now
    // is rather than blinking there. Called later, once all of mpd's reply is
    // in: a new track's duration lands before its elapsed time, and the step
    // between the two would read as a jump forward first. A rewind already
    // under way is let finish rather than restarted by the next second's
    // tick, and lands on wherever the track has got to by then.
    function track() {
        if (!Mpd.loaded || rewind.running)
            return;
        if (root.settled && root.position < root.progress) {
            rewind.to = root.position;
            rewind.restart();
        } else {
            root.progress = root.position;
        }
    }

    onPositionChanged: Qt.callLater(root.track)

    NumberAnimation {
        id: rewind
        target: root
        property: "progress"
        duration: Theme.foldMs
        easing.type: Easing.InOutCubic
        onFinished: root.track()
    }

    // The title and the sleeve, kept while the pill goes: the queue is empty
    // before the pill has gone, and the line should not blank on the way.
    // Taken from mpd only while there is something to show and left holding
    // the last value after.
    property string shownLabel: ""
    property string shownCover: ""
    property string outgoingLabel: ""
    property real titleMix: 1

    // The track's colour, taken off the sleeve the way Apple Music tints what
    // is playing: the record's most vivid colour, lifted to read on dark
    // glass. A grey or colourless sleeve, or none, leaves the line white.
    ColorQuantizer {
        id: palette
        source: root.shownCover
        depth: 3
        rescaleSize: 64
    }

    property color accent: {
        // Not left to the palette, which may go on holding the last sleeve's.
        if (!root.shownCover)
            return Theme.fg;
        const colors = palette.colors;
        let best = null;
        // Below this much colour (saturation times brightness) a sleeve has
        // none worth taking.
        let most = 0.2;
        for (let i = 0; i < colors.length; i++) {
            const vivid = colors[i].hsvSaturation * colors[i].hsvValue;
            if (vivid > most) {
                best = colors[i];
                most = vivid;
            }
        }
        if (!best)
            return Theme.fg;
        return Qt.hsla(best.hslHue, Math.max(best.hslSaturation, 0.5), Math.min(Math.max(best.hslLightness, 0.65), 0.8), 1);
    }

    Behavior on accent {
        ColorAnimation {
            duration: Theme.foldMs
        }
    }

    // The titles overlap as the pill springs to the arriving title's width.
    function follow() {
        if (!Mpd.loaded || (Mpd.label === root.shownLabel && Mpd.cover === root.shownCover))
            return;
        if (Mpd.label !== root.shownLabel) {
            titleFade.stop();
            root.outgoingLabel = root.settled ? root.shownLabel : "";
            root.shownLabel = Mpd.label;
            root.titleMix = 1;
            if (root.outgoingLabel)
                titleFade.restart();
        }
        root.shownCover = Mpd.cover;
    }

    contentAnimating: titleFade.running || previousWidth.running || titleWidth.running || nextWidth.running

    NumberAnimation {
        id: titleFade
        target: root
        property: "titleMix"
        from: 0
        to: 1
        duration: Theme.foldMs
        easing.type: Easing.InOutCubic
        onFinished: root.outgoingLabel = ""
    }

    Connections {
        target: Mpd

        function onLabelChanged() {
            root.follow();
        }
        function onCoverChanged() {
            root.follow();
        }
        function onLoadedChanged() {
            root.follow();
            Qt.callLater(root.track);
        }
    }

    Component.onCompleted: {
        follow();
        track();
    }

    // Each part brings its own gap, so that the hands can take theirs with
    // them as they fold.
    spacing: 0
    popup: MusicPopup {
        accent: root.accent
    }
    // The title opens it (below), not the whole pill.
    popupButton: Qt.NoButton
    // Each target presses in by itself, the title included (PressGlass).
    dips: false

    actions: ({
            [Qt.RightButton]: () => Mpd.toggle()
        })

    // The hands, out only while the pill is pointed at: at rest it is play
    // and the title, and reached for it opens out into prev, play and next. Held out while the popup is up, which the pointer leaves the pill
    // to get to — folding then would slide the popup out from under it.
    readonly property bool handsOut: root.containsMouse || root.popupOpen

    // A hand either side, folding the way a module goes into the drawer: its
    // room closes on the fold's own curve, with no bounce — the pill opening
    // to a hover is the pill answering, not a new title arriving — and the
    // pill's edge passes over the glyph, which stays put beside the title. Its tap is off while folded, where the glyph sits
    // out past the pill's edge.
    Item {
        readonly property real full: prev.implicitWidth + Theme.mediaGap

        Layout.fillHeight: true
        implicitWidth: root.handsOut ? full : 0
        clip: width < full
        opacity: width / full

        Behavior on implicitWidth {
            enabled: root.settled
            NumberAnimation {
                id: previousWidth
                duration: Theme.foldMs
                easing.type: Easing.InOutCubic
            }
        }

        Glyph {
            id: prev
            readonly property bool inkHovered: prevHover.hovered

            HoverHandler { id: prevHover; enabled: root.handsOut }

            anchors.right: parent.right
            anchors.rightMargin: Theme.mediaGap
            height: parent.height
            text: Theme.glyph.mediaPrev
            scale: prevPress.scale

            PressGlass {
                id: prevPress
                icon: prev
                area: prevTap
            }

            // A pixel of margin on every target. Targets used to press in by
            // dipping the item their handler hangs off, which left a pointer
            // on the screen's top pixel — the cheapest place on the bar to
            // click — above the item it had pressed and cancelled the tap.
            // They grow from their middle now (PressGlass), but the margin
            // keeps a press on that pixel landing whatever the press does.
            Accessible.role: Accessible.Button
            Accessible.name: "Previous track"
            Accessible.onPressAction: if (prevTap.enabled && enabled && visible)
                Mpd.prev()

            TapHandler {
                id: prevTap
                enabled: root.handsOut
                margin: Theme.pressDip
                onTapped: Mpd.prev()
            }
        }
    }

    RowLayout {
        Layout.fillHeight: true
        // The play button brings the gap after it.
        spacing: 0

        // With another module's popup up, resting on the title opens this
        // one in its place. BarItem browses only for a module whose whole box
        // is the popup's button, which this one's is not, so the title does it.
        HoverHandler {
            onHoveredChanged: OpenPopup.browse(root, hovered)
        }

        // The pill's play button. Out at rest too, so pausing takes one click
        // rather than a reach for the pill first; with the hands out it sits
        // between them, and the three controls read as one row. The sleeve
        // lives in the popup, and still tints the line (accent above).
        // The gap after it presses with it.
        Item {
            id: slot
            readonly property bool inkHovered: playHover.hovered

            HoverHandler { id: playHover }

            readonly property int size: 14

            Layout.fillHeight: true
            implicitWidth: size + Theme.mediaGap
            scale: playPress.scale

            PressGlass {
                id: playPress
                icon: slot
                area: playTap
            }

            Accessible.role: Accessible.Button
            Accessible.name: Mpd.state === "play" ? "Pause music" : "Play music"
            Accessible.onPressAction: if (enabled && visible)
                Mpd.toggle()

            TapHandler {
                id: playTap
                margin: Theme.pressDip
                onTapped: Mpd.toggle()
            }

            // What pressing it will do, as the popup's own button shows it.
            Glyph {
                x: Math.round((slot.size - width) / 2)
                height: parent.height
                text: Mpd.state === "play" ? Theme.glyph.paused : Theme.glyph.playing
            }
        }

        // The title's room, which is what sizes the pill: it springs to the
        // new title's width rather than jumping there, and the glass drawn off
        // the pill goes with it. The title can enter the end's padding, but
        // stays inside the curve and clear of the next control.
        //
        // And the popup's button, which presses in by itself.
        Item {
            id: titleRoom
            readonly property bool inkHovered: titleHover.hovered

            HoverHandler { id: titleHover }

            // The cap's horizontal room at the text's height, inside the track.
            // A little vertical air also covers hinted strokes and descenders.
            readonly property real endRoom: Math.max(0, root.padRight - Theme.pillTrack - Theme.pillRadius
                + Math.sqrt(Math.max(0, Theme.pillRadius * Theme.pillRadius - Math.pow((title.fontSize + 4) / 2, 2))))
            readonly property real availableWidth: width + Math.min(endRoom,
                Theme.mediaGap + Math.max(0, endRoom - nextRoom.width))
            property real playbackOpacity: Mpd.state === "play" ? 1 : Theme.dimOpacity

            Behavior on playbackOpacity {
                NumberAnimation {
                    duration: Theme.fadeMs
                }
            }

            Layout.fillHeight: true
            implicitWidth: title.implicitWidth
            scale: titlePress.scale

            PressGlass {
                id: titlePress
                icon: titleRoom
                area: popupTap
            }

            Accessible.role: Accessible.Button
            Accessible.name: "Music"
            Accessible.onPressAction: if (enabled && visible)
                root.togglePopup()

            TapHandler {
                id: popupTap
                margin: Theme.pressDip
                onTapped: root.togglePopup()
            }

            Behavior on implicitWidth {
                enabled: root.settled
                SpringAnimation {
                    id: titleWidth
                    spring: Theme.springStiffness
                    // Give the second rebound enough travel to read as a bounce.
                    // The side pills' damping, which Reduce motion calms too.
                    damping: Theme.foldDamping
                    epsilon: 0.25
                }
            }

            BarText {
                id: title

                width: Math.min(implicitWidth, titleRoom.availableWidth)
                height: parent.height
                clip: true
                text: root.shownLabel
                maxWidth: Theme.mediaTitleWidth
                // Paused is the title gone quiet rather than a second icon
                // saying so: an icon that only reports would be the one thing
                // in the pill that cannot be pressed.
                opacity: titleRoom.playbackOpacity * root.titleMix
            }

            BarText {
                width: Math.min(implicitWidth, titleRoom.availableWidth)
                height: parent.height
                clip: true
                text: root.outgoingLabel
                maxWidth: Theme.mediaTitleWidth
                visible: root.titleMix < 1 && text !== ""
                opacity: titleRoom.playbackOpacity * (1 - root.titleMix)
            }
        }
    }

    Item {
        id: nextRoom

        readonly property real full: Theme.mediaGap + next.implicitWidth

        Layout.fillHeight: true
        implicitWidth: root.handsOut ? full : 0
        clip: width < full
        opacity: width / full

        Behavior on implicitWidth {
            enabled: root.settled
            NumberAnimation {
                id: nextWidth
                duration: Theme.foldMs
                easing.type: Easing.InOutCubic
            }
        }

        Glyph {
            id: next
            readonly property bool inkHovered: nextHover.hovered

            HoverHandler { id: nextHover; enabled: root.handsOut }

            x: Theme.mediaGap
            height: parent.height
            text: Theme.glyph.mediaNext
            scale: nextPress.scale

            PressGlass {
                id: nextPress
                icon: next
                area: nextTap
            }

            Accessible.role: Accessible.Button
            Accessible.name: "Next track"
            Accessible.onPressAction: if (nextTap.enabled && enabled && visible)
                Mpd.next()

            TapHandler {
                id: nextTap
                enabled: root.handsOut
                margin: Theme.pressDip
                onTapped: Mpd.next()
            }
        }
    }

    scrolls: true
    Accessible.onScrollUpAction: scrollUp()
    Accessible.onScrollDownAction: scrollDown()
    onScrollUp: Mpd.seek(-10)
    onScrollDown: Mpd.seek(10)
}

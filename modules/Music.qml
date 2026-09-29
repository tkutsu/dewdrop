import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs
import qs.components
import qs.services

// The music pill: what is playing, and when pointed at, a hand either side of
// it. The title opens the popup — it is the widest thing in the pill and the
// one you are already looking at, so it is also the cheapest to hit. The
// sleeve's slot is play/pause, and so is a right click anywhere on the pill.
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
    stowed: !Mpd.loaded || !Settings.moduleOn("music")
    folds: false

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

    // The track's colour, taken off the sleeve the way Apple Music tints what
    // is playing: the record's most vivid colour, lifted to read on dark
    // glass. A grey or colourless sleeve, or none, leaves the line white.
    // Off the shown sleeve, so it turns with the swap rather than ahead of it.
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

    // A new track is not swapped in under the eye: title and sleeve dip out
    // together, change while they cannot be seen, and come back as the pill
    // runs to the new title's width.
    function follow() {
        if (!Mpd.loaded || (Mpd.label === root.shownLabel && Mpd.cover === root.shownCover))
            return;
        if (root.settled) {
            swap.restart();
        } else {
            root.shownLabel = Mpd.label;
            root.shownCover = Mpd.cover;
        }
    }

    property real swapOpacity: 1

    SequentialAnimation {
        id: swap

        NumberAnimation {
            target: root
            property: "swapOpacity"
            to: 0
            duration: Theme.fadeMs / 2
            easing.type: Easing.InQuad
        }
        ScriptAction {
            script: {
                if (!Mpd.loaded)
                    return;
                root.shownLabel = Mpd.label;
                root.shownCover = Mpd.cover;
            }
        }
        NumberAnimation {
            target: root
            property: "swapOpacity"
            to: 1
            duration: Theme.foldMs
            easing.type: Easing.OutCubic
        }
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
    popup: MusicPopup {}
    // The title opens it (below), not the whole pill.
    popupButton: Qt.NoButton
    // Each target presses in by itself; the pill as a whole does not.
    dips: false

    actions: ({
            [Qt.RightButton]: () => Mpd.send(["toggle"])
        })

    // The controls, out only while the pill is pointed at: at rest it is the
    // sleeve and the title, and reached for it opens out into prev, play and
    // next. Held out while the popup is up, which the pointer leaves the pill
    // to get to — folding then would slide the popup out from under it.
    readonly property bool handsOut: root.containsMouse || root.popupOpen

    // A hand either side, folding the way a module goes into the drawer: its
    // room springs shut and the pill's edge passes over the glyph, which stays
    // put beside the title. Its tap is off while folded, where the glyph sits
    // out past the pill's edge.
    Item {
        readonly property real full: prev.implicitWidth + Theme.mediaGap

        Layout.fillHeight: true
        implicitWidth: root.handsOut ? full : 0
        clip: width < full
        opacity: Math.min(1, width / full)

        Behavior on implicitWidth {
            enabled: root.settled
            SpringAnimation {
                spring: Theme.springStiffness
                damping: Theme.springDamping
                epsilon: 0.25
            }
        }

        Glyph {
            id: prev

            anchors.right: parent.right
            anchors.rightMargin: Theme.mediaGap
            height: parent.height
            text: Theme.glyph.mediaPrev
            transform: Translate { y: prevTap.pressed ? Theme.pressDip : 0 }

            // A margin of the dip's own depth, on every target. Each presses
            // in by moving the item its handler hangs off, and a pointer on
            // the screen's top pixel — the cheapest place on the bar to click
            // — was left a pixel above the item it had pressed, which
            // cancelled the tap before the button came up. BarItem's own click
            // never had this: what dips there is the contents, not the
            // MouseArea.
            TapHandler {
                id: prevTap
                enabled: root.handsOut
                margin: Theme.pressDip
                onTapped: Mpd.send(["prev"])
            }
        }
    }

    // The sleeve and the title, which change together with the track.
    //
    // The swap is a blur-replace, the way the Dynamic Island changes what it
    // shows: going, they soften, shrink a touch and fade; coming, the reverse.
    // Blurred through a layer only while it runs, so the pill at rest is
    // drawn as it always was.
    RowLayout {
        Layout.fillHeight: true
        // The sleeve brings the gap after it, so the two come and go together.
        spacing: 0
        opacity: root.swapOpacity
        scale: 0.92 + 0.08 * root.swapOpacity

        layer.enabled: root.swapOpacity < 1
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 12
            blur: 1 - root.swapOpacity
        }

        // With another module's popup up, arriving on the title opens this
        // one in its place. BarItem browses only for a module whose whole box
        // is the popup's button, which this one's is not, so the title does it.
        HoverHandler {
            onHoveredChanged: if (hovered)
                OpenPopup.browse(root)
        }

        // The sleeve, as the title's own icon and the pill's play button. It
        // is the one spot of colour on a bar that is otherwise white on dark,
        // and it changes with every record — the thing that says which album
        // this is before the title has been read. The popup already had the
        // picture; this is a thumbnail of the same file.
        //
        // Icon-sized and only just rounded, so it reads as part of the row
        // rather than as a second pill inside this one. With the hands out it
        // gives its place to a play or pause mark between them, so the three
        // controls read as one row; at rest the picture is back. A folder
        // with no sleeve shows the mark at rest too, so the slot is never
        // empty. The gap after it presses with it.
        Item {
            id: slot

            readonly property int size: 14
            readonly property int air: (Theme.barHeight - size) / 2
            // Nothing to show rather than something still decoding: a record
            // whose picture is on its way fades straight into it.
            readonly property bool bare: sleeve.status === Image.Null || sleeve.status === Image.Error

            Layout.fillHeight: true
            implicitWidth: size + Theme.mediaGap
            transform: Translate { y: playTap.pressed ? Theme.pressDip : 0 }

            TapHandler {
                id: playTap
                margin: Theme.pressDip
                onTapped: Mpd.send(["toggle"])
            }

            ClippingRectangle {
                y: Theme.pillTop(parent.height) + parent.air
                width: parent.size
                height: parent.size
                radius: 3
                color: "transparent"

                Image {
                    id: sleeve

                    anchors.fill: parent
                    source: root.shownCover
                    fillMode: Image.PreserveAspectCrop
                    // Decoded at twice the size it is drawn, not at the size of
                    // the scan: some of these are 1400px across.
                    sourceSize.width: parent.width * 2
                    sourceSize.height: parent.height * 2
                    asynchronous: true
                    smooth: true
                    mipmap: true
                    opacity: status === Image.Ready && !root.handsOut ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.fadeMs
                        }
                    }
                }
            }

            // What pressing it will do, as the popup's own button shows it.
            Glyph {
                x: Math.round((slot.size - width) / 2)
                height: parent.height
                text: Mpd.state === "play" ? Theme.glyph.paused : Theme.glyph.playing
                opacity: root.handsOut || slot.bare ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.fadeMs
                    }
                }
            }
        }

        // The title's room, which is what sizes the pill: it springs to the
        // new title's width rather than jumping there, and the glass drawn off
        // the pill goes with it. Clipped only on the way.
        //
        // And the popup's button, which presses in by itself.
        Item {
            Layout.fillHeight: true
            implicitWidth: title.implicitWidth
            clip: width !== title.implicitWidth
            transform: Translate { y: popupTap.pressed ? Theme.pressDip : 0 }

            TapHandler {
                id: popupTap
                margin: Theme.pressDip
                onTapped: root.togglePopup()
            }

            Behavior on implicitWidth {
                enabled: root.settled
                SpringAnimation {
                    spring: Theme.springStiffness
                    damping: Theme.springDamping
                    epsilon: 0.25
                }
            }

            BarText {
                id: title

                height: parent.height
                text: root.shownLabel
                maxWidth: Theme.mediaTitleWidth
                // Paused is the title gone quiet rather than a second icon
                // saying so: an icon that only reports would be the one thing
                // in the pill that cannot be pressed.
                opacity: Mpd.state === "play" ? 1 : Theme.dimOpacity

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.fadeMs
                    }
                }
            }
        }
    }

    Item {
        readonly property real full: Theme.mediaGap + next.implicitWidth

        Layout.fillHeight: true
        implicitWidth: root.handsOut ? full : 0
        clip: width < full
        opacity: Math.min(1, width / full)

        Behavior on implicitWidth {
            enabled: root.settled
            SpringAnimation {
                spring: Theme.springStiffness
                damping: Theme.springDamping
                epsilon: 0.25
            }
        }

        Glyph {
            id: next

            x: Theme.mediaGap
            height: parent.height
            text: Theme.glyph.mediaNext
            transform: Translate { y: nextTap.pressed ? Theme.pressDip : 0 }

            TapHandler {
                id: nextTap
                enabled: root.handsOut
                margin: Theme.pressDip
                onTapped: Mpd.send(["next"])
            }
        }
    }

    onScrollUp: Mpd.send(["seek", "-10"])
    onScrollDown: Mpd.send(["seek", "+10"])
}

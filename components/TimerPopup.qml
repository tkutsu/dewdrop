import QtQuick
import qs
import qs.components
import qs.services

// The timer pill's popup: everything that is set, and a way to set something
// else.
//
// The pill itself only ever shows one timer — the one nearest its end — which
// is the right answer to a glance and the wrong one to a question. This is the
// question: all of them, each with the things that can be done to it.
Popup {
    id: root

    readonly property int bodyWidth: 236
    readonly property int rowHeight: 22

    // The readout is a fixed column rather than as wide as what it says. It
    // changes every second, and a popup that sized itself to it would ask the
    // compositor to reposition the window once a second for as long as it was
    // open — see Popup.reserveHeight for what that looks like.
    readonly property int readoutWidth: 48
    readonly property int buttonWidth: 20
    readonly property int gutter: 18

    spacing: 6

    // Ringing first, because it is the only row here that is asking for
    // something. Then what is running, then the alarms standing by — soonest
    // first inside each group, which is the order they will matter in.
    // Nothing in here may read Timers.now, and that is the whole point of the
    // way it is written.
    //
    // This list is a Repeater's model. A model is replaced by rebuilding the
    // array, and replacing it destroys every delegate and builds it again — so
    // a list that mentioned the time left would be torn down and rebuilt once a
    // second. Qt only works out which item is under the pointer when the
    // pointer moves, so after each rebuild the hover was left on whichever item
    // had inherited that position: pointing at the first row lit the third, and
    // the middle rows lit nothing at all. A click would have gone the same way,
    // which is a timer cancelled that nobody aimed at.
    //
    // So the model carries the entry and the delegate reads the clock off it.
    // What changes every second is then one Text binding per row instead of the
    // rows themselves.
    readonly property var rows: {
        const out = [];

        for (const e of Timers.ringing)
            out.push({
                key: "ring:" + e.id,
                entry: null,
                glyph: Theme.glyph.timerRing,
                warn: true,
                dim: false,
                title: Timers.ringTitle(e),
                readout: "",
                buttons: [
                    {
                        glyph: Theme.glyph.powerCancel,
                        act: () => Timers.hush()
                    }
                ]
            });

        // The same order "soonest first" always gave, off numbers that do not
        // move: running timers all count down together, so sorting them on when
        // they end is sorting them on what is left. A held one has no end to
        // sort on and goes below, in the order it was held at.
        const live = Timers.timers.slice().sort((a, b) => {
            if (a.running !== b.running)
                return a.running ? -1 : 1;
            return a.running ? a.endsAt - b.endsAt : a.left - b.left;
        });
        for (const e of live)
            out.push({
                key: "timer:" + e.id,
                entry: e,
                glyph: e.running ? Theme.glyph.timer : Theme.glyph.timerPaused,
                warn: false,
                dim: !e.running,
                title: e.label !== "" ? e.label : "Timer",
                // Left to the delegate, off `entry` above.
                readout: "",
                buttons: [
                    {
                        glyph: e.running ? Theme.glyph.paused : Theme.glyph.playing,
                        act: () => Timers.toggle(e.id)
                    },
                    {
                        glyph: Theme.glyph.powerCancel,
                        act: () => Timers.cancel(e.id)
                    }
                ]
            });

        const set = Timers.alarms.slice().sort((a, b) => a.endsAt - b.endsAt);
        for (const e of set)
            out.push({
                key: "alarm:" + e.id,
                // An alarm's readout is a wall-clock time and does not count
                // down, so it stays in the model where it is cheapest.
                entry: null,
                glyph: Theme.glyph.alarm,
                warn: false,
                // A switched-off alarm stays on the list rather than leaving
                // it: it is still a thing you set, and finding it again is the
                // whole difference between turning one off and cancelling it.
                dim: !e.running,
                title: e.label !== "" ? e.label : "Alarm",
                readout: Timers.hhmm(e.hour, e.minute),
                buttons: [
                    {
                        glyph: e.running ? Theme.glyph.paused : Theme.glyph.playing,
                        act: () => Timers.toggle(e.id)
                    },
                    {
                        glyph: Theme.glyph.powerCancel,
                        act: () => Timers.cancel(e.id)
                    }
                ]
            });

        return out;
    }

    PopupHeader {
        width: root.bodyWidth
        // Level with the rows' glyphs.
        inset: 2
        title: "Timers"

        // The way in to setting another: the launcher, which takes any
        // duration or time of day.
        PopupButton {
            framed: true
            glyph: Theme.glyph.plus
            onTapped: Launcher.openWith(Launcher.taskPrefix)
        }
    }

    PopupText {
        visible: Timers.phoneWarning !== ""
        width: root.bodyWidth
        text: Timers.phoneWarning
        color: Theme.warn
        font.pixelSize: Theme.footnoteSize
        wrapMode: Text.WordWrap
    }

    PopupText {
        visible: root.rows.length === 0
        width: root.bodyWidth
        text: "Nothing set"
        opacity: 0.6
    }

    Repeater {
        model: root.rows

        delegate: PopupRow {
            id: row

            required property var modelData

            width: root.bodyWidth
            height: root.rowHeight

            Glyph {
                x: 2
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.glyph
                fontSize: Theme.popupGlyphSize
                implicitHeight: root.rowHeight
                color: row.modelData.warn ? Theme.warn : Theme.fg
                opacity: row.modelData.dim ? 0.45 : 1
            }

            PopupText {
                anchors {
                    left: parent.left
                    leftMargin: root.gutter + 6
                    right: readout.left
                    rightMargin: 6
                    verticalCenter: parent.verticalCenter
                }
                text: row.modelData.title
                color: row.modelData.warn ? Theme.warn : Theme.fg
                font.pixelSize: Theme.captionSize
                opacity: row.modelData.dim ? 0.45 : 0.9
                elide: Text.ElideRight
            }

            // Tabular figures, right-aligned in a fixed column: the digits change
            // every second and the column must not move as they do, or a row
            // that is only counting looks like a row that is being edited.
            PopupText {
                id: readout

                anchors {
                    right: buttons.left
                    rightMargin: 6
                    verticalCenter: parent.verticalCenter
                }
                width: root.readoutWidth
                horizontalAlignment: Text.AlignRight
                // The one thing on a row that moves. A binding here rather
                // than a value in the model is what keeps the row itself still.
                text: row.modelData.entry ? Timers.clock(Timers.remaining(row.modelData.entry)) : row.modelData.readout
                font.pixelSize: Theme.captionSize
                opacity: row.modelData.dim ? 0.45 : 0.75
            }

            // Always drawn rather than appearing on hover: these rows are
            // short-lived and a control that has to be found by hovering is one
            // more second than a ringing alarm deserves. They are quiet until
            // the pointer is on them instead.
            Row {
                id: buttons

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: root.rowHeight
                spacing: 0

                Repeater {
                    model: row.modelData.buttons

                    delegate: PopupButton {
                        required property var modelData

                        width: root.buttonWidth
                        height: root.rowHeight
                        glyph: modelData.glyph
                        onTapped: modelData.act()
                    }
                }
            }
        }
    }
}

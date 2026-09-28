import QtQuick
import qs

// Figures that roll to their next value, the way the Dynamic Island's timer
// counts (SwiftUI's numericText): one column per character, and a figure that
// changes slides out one way while the one after it comes in from the other,
// fading as they pass. The columns that did not change hold still, so a
// timer's seconds tick over and its minutes stay put.
//
// For figures only. The colon just changes, and a string that is words is
// better drawn by BarText, which keeps the kerning a column per letter loses.
Row {
    id: root

    property string text: ""
    // Counting down, the figures drop: the next one comes in from above.
    property bool countsDown: false
    property color color: Theme.fg

    // Counted from the right, where the figures that change are: a string
    // that gains or loses a figure (10:00 to 9:59) does it at the left end,
    // and every other column keeps the place it had.
    layoutDirection: Qt.RightToLeft

    Repeater {
        // A fixed number of columns, the ones past the end of the string empty
        // and of no width: a Repeater given a count rebuilds every column when
        // the count changes, and 10:00 to 9:59 would swap rather than roll.
        // Eight is 99:59:59.
        model: Math.max(8, root.text.length)

        delegate: Item {
            id: column

            required property int index
            // Empty past the start of the string (charAt of a negative index).
            readonly property string ch: root.text.charAt(root.text.length - 1 - index)
            // What the column shows and what it last showed, set here rather
            // than bound: the change handler needs the old one.
            property string shown: ""
            property string was: ""
            // How far through the roll, 0..1; 1 is at rest.
            property real t: 1
            readonly property real travel: Math.round(Theme.textSize * 0.6) * (root.countsDown ? -1 : 1)

            // An empty column counts: a figure arriving at the left end, or
            // leaving it, rolls in or out like any other.
            function rolls(c) {
                return c === "" || (c >= "0" && c <= "9");
            }

            onChChanged: {
                if (rolls(ch) && rolls(shown) && root.visible) {
                    was = shown;
                    shown = ch;
                    roll.restart();
                } else {
                    roll.stop();
                    shown = ch;
                    t = 1;
                }
            }
            Component.onCompleted: shown = ch

            // From the old figure's width to the new one's as it rolls, which
            // only ever differs for a column coming or going: the figures are
            // tabular. The row closes up behind a figure leaving rather than
            // dropping it on its neighbour.
            implicitWidth: t < 1 ? old.implicitWidth + (now.implicitWidth - old.implicitWidth) * t : now.implicitWidth
            height: root.height

            NumberAnimation {
                id: roll
                target: column
                property: "t"
                from: 0
                to: 1
                duration: Theme.rollMs
                easing.type: Easing.OutCubic
            }

            // No blur on the way, unlike SwiftUI's: at this size it barely
            // showed, and it cost 0.6% CPU while a timer ran (1.8% against
            // 2.4%, measured) for a roll that happens every second.

            BarText {
                id: now
                height: parent.height
                text: column.shown
                color: root.color
                y: (1 - column.t) * column.travel
                opacity: column.t
            }

            BarText {
                id: old
                height: parent.height
                visible: column.t < 1
                text: column.was
                color: root.color
                y: -column.t * column.travel
                opacity: 1 - column.t
            }
        }
    }
}

import QtQuick
import QtQuick.Effects
import qs

// Figures that roll to their next value the way SwiftUI's numericText does,
// which is how the Dynamic Island's timer counts: one column per character,
// and only the columns that change move, so a timer's seconds tick over and
// its minutes stay put.
//
// A changing figure is not cross-faded. The one leaving travels a third of a
// line and shrinks to 40% as it blurs out; the one arriving comes from a third
// of a line the other way, growing from 40% as it comes into focus, and its
// travel is a spring that runs a little past its place and comes back. Four
// clocks, each the step response of a damped spring: the figures are SwiftUI's
// own, fitted frame by frame to its transition at 60 fps (RollingEngine.hpp in
// react-native-nitro-rolling-number). Their opacity goes with their size, so
// what reads is a figure falling away small and blurred, never two figures
// dissolving through each other.
//
// The blur is half SwiftUI's. At bar sizes its full blur smeared a figure
// across most of its own width, and the roll read as out of focus rather than
// as moving.
//
// For figures only. The colon just changes, and a string that is words is
// better drawn by BarText, which keeps the kerning a column per letter loses.
Row {
    id: root

    property string text: ""
    property int columns: 8
    // Counting down, the figures drop: the next one comes in from above.
    property bool countsDown: false
    property color color: Theme.fg
    property int fontSize: Theme.textSize
    property int weight: Theme.bodyWeight

    // SwiftUI's transition, in line heights and in multiples of its duration
    // (Theme.rollMs).
    readonly property real offset: 0.34
    readonly property real smallest: 0.4
    readonly property real blurLines: 0.04
    // The travel's spring rings past 2% at one duration; SwiftUI lets it
    // settle, and so does this.
    readonly property real tail: 1.45

    readonly property real line: metrics.height

    FontMetrics {
        id: metrics
        font.family: Theme.bodyFont
        font.pixelSize: root.fontSize
        font.weight: root.weight
    }

    // A damped spring's step response at time t, with damping ratio zeta,
    // scaled to settle within 2% at `settle` (all in durations).
    function damped(t, zeta, settle) {
        if (t <= 0)
            return 0;
        if (zeta >= 0.999) {
            const k = 5.83 / settle;
            return 1 - (1 + k * t) * Math.exp(-k * t);
        }
        const omega = 4 / (zeta * settle);
        const k = zeta * omega;
        const wd = omega * Math.sqrt(1 - zeta * zeta);
        return 1 - Math.exp(-k * t) * (Math.cos(wd * t) + (k / wd) * Math.sin(wd * t));
    }

    // Counted from the right, where the figures that change are: a string
    // that gains or loses a figure (10:00 to 9:59) does it at the left end,
    // and every other column keeps the place it had.
    layoutDirection: Qt.RightToLeft

    Repeater {
        // A fixed number of columns, the ones past the end of the string empty
        // and of no width: a Repeater given a count rebuilds every column when
        // the count changes, and 10:00 to 9:59 would swap rather than roll.
        // Eight is 99:59:59.
        model: Math.max(root.columns, root.text.length)

        delegate: Item {
            id: column

            required property int index
            // Empty past the start of the string (charAt of a negative index).
            readonly property string ch: root.text.charAt(root.text.length - 1 - index)
            // What the column shows and what it last showed, set here rather
            // than bound: the change handler needs the old one.
            property string shown: ""
            property string was: ""

            // Time into the roll, in durations; at rest every clock reads 1.
            property real s: root.tail
            readonly property bool rolling: roll.running
            // The travel (overshoots), the size and opacity, the arriving
            // figure's focus and the leaving one's blur.
            readonly property real b: rolling ? root.damped(s, 0.54, 1) : 1
            readonly property real g: rolling ? root.damped(s, 1, 0.65) : 1
            readonly property real f: rolling ? root.damped(s, 0.85, 0.74) : 1
            readonly property real o: rolling ? root.damped(s, 1, 0.46) : 1
            // Down the screen for a figure coming in from above.
            readonly property real travel: root.offset * root.line * (root.countsDown ? 1 : -1)

            // An empty column counts: a figure arriving at the left end, or
            // leaving it, rolls in or out like any other.
            function rolls(c) {
                return c === "" || (c >= "0" && c <= "9");
            }

            onChChanged: {
                // Under Reduce motion a figure is swapped rather than rolled.
                if (rolls(ch) && rolls(shown) && root.visible && !Theme.reduceMotion) {
                    was = shown;
                    shown = ch;
                    roll.restart();
                } else {
                    roll.stop();
                    shown = ch;
                }
            }
            Component.onCompleted: shown = ch

            // From the old figure's width to the new one's as it grows, which
            // only ever differs for a column coming or going: the figures are
            // tabular. The row closes up behind a figure leaving rather than
            // dropping it on its neighbour.
            implicitWidth: rolling ? old.implicitWidth + (now.implicitWidth - old.implicitWidth) * g : now.implicitWidth
            height: root.height

            NumberAnimation {
                id: roll
                target: column
                property: "s"
                from: 0
                to: root.tail
                duration: Theme.rollMs * root.tail
            }

            BarText {
                id: now

                readonly property real blur: 1 - column.f

                height: parent.height
                fontSize: root.fontSize
                weight: root.weight
                text: column.shown
                color: root.color
                y: -column.travel * (1 - column.b)
                scale: root.smallest + (1 - root.smallest) * column.g
                opacity: column.g

                // Only while the blur shows: MultiEffect left on at no blur
                // lays a grey veil over the figure and everything under it.
                // Smooth, because the figure moves by fractions of a pixel and
                // shrinks, and a texture sampled to the nearest pixel moves in
                // whole pixels and sheds rows as it goes.
                layer.enabled: blur > 0.02
                layer.smooth: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blurMax: Math.ceil(root.blurLines * root.line * 2)
                    blur: now.blur
                }
            }

            BarText {
                id: old

                readonly property real blur: column.o

                height: parent.height
                visible: column.rolling
                fontSize: root.fontSize
                weight: root.weight
                text: column.was
                color: root.color
                y: column.travel * column.b
                scale: 1 - (1 - root.smallest) * column.g
                opacity: 1 - column.g

                layer.enabled: visible && blur > 0.02
                layer.smooth: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blurMax: Math.ceil(root.blurLines * root.line * 2)
                    blur: old.blur
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Effects
import qs.src.core
import "RollingSpring.js" as Spring

// Figures that roll to their next value the way a stopwatch counts: one
// column per character, and only the columns that change move, so a timer's
// seconds tick over and its minutes stay put.
//
// A changing figure is not cross-faded. The one leaving travels a third of a
// line and shrinks to 40% as it blurs out; the one arriving comes from a third
// of a line the other way, growing from 40% as it comes into focus, and its
// travel is a spring that runs a little past its place and comes back. Four
// clocks, each the step response of a damped spring: the figures are fitted
// frame by frame to a reference transition at 60 fps (RollingEngine.hpp in
// react-native-nitro-rolling-number). Their opacity goes with their size, so
// what reads is a figure falling away small and blurred, never two figures
// dissolving through each other.
//
// The blur is half the reference's. At bar sizes its full blur smeared a figure
// across most of its own width, and the roll read as out of focus rather than
// as moving.
//
// For figures only. The colon just changes, and a string that is words is
// better drawn by BarText, which keeps the kerning a column per letter loses.
//
// On the bar it centres on its capitals in a box the bar's height, as BarText
// does. Off the bar (asText) it sits where a Text item would: its top at the
// item's, its baseline at the font's ascent, as tall as a Text, so it can
// replace one without the line moving.
Row {
    id: root

    property string text: ""
    property int columns: 8
    // Counting down, the figures drop: the next one comes in from above.
    property bool countsDown: false
    property color color: Theme.fg
    property int fontSize: Theme.textSize
    property int weight: Theme.bodyWeight
    // Trim only the run's outer edges; keep the internal character advances.
    property bool tightWidth: false
    // Character ranges drawn two-thirds size: on the full-size text's
    // baseline, or raised to its capitals' tops where a range says
    // `shift: "sup"` (ScriptMetrics).
    property var smallRanges: []
    // Their size against the full text's.
    property alias smallRatio: scripts.smallRatio
    readonly property int smallFontSize: scripts.smallFontSize
    // Added after each character, as a Text item's letterSpacing is.
    property real letterSpacing: 0
    property bool asText: false

    // The reference transition, in line heights and in multiples of its duration
    // (Theme.rollMs).
    readonly property real offset: 0.34
    readonly property real smallest: 0.4
    readonly property real blurLines: 0.04
    // The travel's spring rings past 2% at one duration; the reference
    // lets it settle, and so does this.
    readonly property real tail: 1.45

    readonly property real line: scripts.full.height
    // The box BarText centres the capitals in. As text, the one that puts the
    // text's top at 0: BarText's top is (box + capitals) / 2 - ascent.
    readonly property real box: root.asText ? 2 * scripts.full.ascent - scripts.full.capitalHeight : root.height

    baselineOffset: scripts.top(scripts.full) + scripts.full.ascent

    ScriptMetrics {
        id: scripts
        fontSize: root.fontSize
        weight: root.weight
        height: root.box
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
            readonly property var range: root.smallRanges.find(range => {
                const position = root.text.length - 1 - index;
                return position >= range.start && position < range.end;
            }) ?? null
            readonly property bool small: range !== null
            readonly property int nudge: small ? scripts.nudge(range.shift ?? "") : 0
            // What the column shows and what it last showed, set here rather
            // than bound: the change handler needs the old one.
            property string shown: ""
            property string was: ""

            // Time into the roll, in durations; at rest every clock reads 1.
            property real s: root.tail
            readonly property bool rolling: roll.running
            // The travel (overshoots), the size and opacity, the arriving
            // figure's focus and the leaving one's blur.
            readonly property real b: rolling ? Spring.damped(s, 0.54, 1) : 1
            readonly property real g: rolling ? Spring.damped(s, 1, 0.65) : 1
            readonly property real f: rolling ? Spring.damped(s, 0.85, 0.74) : 1
            readonly property real o: rolling ? Spring.damped(s, 1, 0.46) : 1
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
            // The spacing goes with the figure: in as it arrives in an
            // empty column, out as it leaves one.
            readonly property real spaced: root.letterSpacing * (rolling ? (was ? 1 : 0) + ((shown ? 1 : 0) - (was ? 1 : 0)) * g : (shown ? 1 : 0))
            implicitWidth: (rolling ? old.implicitWidth + (now.implicitWidth - old.implicitWidth) * g : now.implicitWidth) + spaced
            height: root.asText ? root.line : root.height

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

                height: root.box
                fontSize: column.small ? root.smallFontSize : root.fontSize
                nudge: column.nudge
                weight: root.weight
                text: column.shown
                trimLeft: root.tightWidth && column.index === root.text.length - 1
                trimRight: root.tightWidth && column.index === 0
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

                height: root.box
                visible: column.rolling
                fontSize: column.small ? root.smallFontSize : root.fontSize
                nudge: column.nudge
                weight: root.weight
                text: column.was
                trimLeft: root.tightWidth && column.index === root.text.length - 1
                trimRight: root.tightWidth && column.index === 0
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

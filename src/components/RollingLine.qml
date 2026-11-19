import QtQuick
import qs.src.core

// A line of text whose figures roll (RollingText) and whose words keep their
// kerning: drawn a column per letter, as RollingText draws, "Friday" and
// "November" came apart at the lock screen's size. The line is cut into runs
// of figures and runs of everything else, laid out as a Text would lay it
// out; a run of figures rolls to its next value, a run of words just changes.
//
// Runs are kept by their place in the line, so "20" to "21" rolls where it
// stands, as long as the line keeps its shape (a date's always does).
Row {
    id: root

    // A Settings.timeDisplay: the text and its small runs.
    property var display: ({ text: "", smallRanges: [] })
    property int fontSize: Theme.textSize
    property int weight: Theme.bodyWeight
    property color color: Theme.fg
    property real smallRatio: 2 / 3

    readonly property var runs: {
        const text = root.display.text;
        const runs = [];
        const pieces = /\d+|\D+/g;
        let match;
        while ((match = pieces.exec(text)) !== null) {
            const start = match.index;
            const end = start + match[0].length;
            runs.push({
                text: match[0],
                figures: /\d/.test(match[0][0]),
                smallRanges: root.display.smallRanges.filter(range => range.start < end && range.end > start).map(range => ({
                    start: Math.max(range.start, start) - start,
                    end: Math.min(range.end, end) - start,
                    shift: range.shift
                }))
            });
        }
        return runs;
    }

    baselineOffset: metrics.ascent

    FontMetrics {
        id: metrics
        font.family: Theme.bodyFont
        font.pixelSize: root.fontSize
        font.weight: root.weight
    }

    Repeater {
        model: root.runs.length

        Item {
            id: run

            required property int index
            readonly property var piece: root.runs[run.index] ?? { text: "", figures: false, smallRanges: [] }

            width: run.piece.figures ? figures.implicitWidth : words.implicitWidth
            height: words.implicitHeight

            RollingText {
                id: figures
                y: words.baselineOffset - figures.baselineOffset
                visible: run.piece.figures
                asText: true
                text: run.piece.figures ? run.piece.text : ""
                smallRanges: run.piece.figures ? run.piece.smallRanges : []
                smallRatio: root.smallRatio
                color: root.color
                fontSize: root.fontSize
                weight: root.weight
            }

            // Laid out under a run of figures too, for the line's height and
            // baseline. Rich text for the small runs, its spaces kept as
            // no-break spaces: rich text drops a run's leading space.
            Text {
                id: words
                opacity: run.piece.figures ? 0 : 1
                textFormat: Text.RichText
                text: run.piece.figures ? "&nbsp;" : Settings.timeMarkup({
                    text: run.piece.text.replace(/ /g, " "),
                    smallRanges: run.piece.smallRanges
                }, root.fontSize, root.smallRatio)
                color: root.color
                font.family: Theme.bodyFont
                font.pixelSize: root.fontSize
                font.weight: root.weight
            }
        }
    }
}

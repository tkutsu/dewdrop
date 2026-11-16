import QtQuick
import qs.src.core

// Where two-thirds-size text goes beside full-size text in a box `height` tall.
// A subscript is a small AM/PM: it stands on the full text's baseline. A
// superscript is the same run raised until its capitals' tops meet the full
// text's. Whole pixels, because BarText draws on whole pixels.
QtObject {
    id: root

    property int fontSize: Theme.textSize
    property int weight: Theme.bodyWeight
    property real height: Theme.barHeight

    readonly property int smallFontSize: Math.max(1, Math.round(root.fontSize * 2 / 3))

    readonly property FontMetrics full: FontMetrics {
        font.family: Theme.bodyFont
        font.pixelSize: root.fontSize
        font.weight: root.weight
    }

    readonly property FontMetrics small: FontMetrics {
        font.family: Theme.bodyFont
        font.pixelSize: root.smallFontSize
        font.weight: root.weight
    }

    // BarText puts a line's top at this, before its nudge.
    function top(metrics: FontMetrics): int {
        return Math.round((root.height + metrics.capitalHeight) / 2 - metrics.ascent);
    }

    readonly property int onBaseline: Math.round(root.top(root.full) + root.full.ascent - (root.top(root.small) + root.small.ascent))
    readonly property int lift: Math.round(root.full.capitalHeight - root.small.capitalHeight)

    // `shift` is "sup", or anything else ("sub", an AM/PM) for the baseline.
    function nudge(shift: string): int {
        return root.onBaseline - (shift === "sup" ? root.lift : 0);
    }
}

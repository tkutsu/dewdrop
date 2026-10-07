import QtQuick
import qs
import qs.components
import qs.services

// The list itself: everything open, soonest first.
//
// No headings and no group names. They spent a row each announcing what the
// dates under them already said, and a list read top to bottom needs neither —
// what is late is at the top because it is the oldest date, which is the same
// place a heading would have put it. What each row keeps is a dot, which says
// how pressing it is in the one glance the list is meant to take.
//
// A row wraps rather than eliding. A task is a sentence somebody wrote to
// themselves and the end of it is usually the part that says what to actually
// do — "ring the surgery about the…" is a row that has to be opened somewhere
// else to be any use, which is the opposite of what a popup on the bar is for.
// So rows are as tall as their text, and the list is as tall as its rows.
//
// The whole row is the button. The circle used to be the only target, which is
// eight pixels of a row twenty-one pixels tall — everywhere else on the row did
// nothing at all, which is a large, inviting, inert surface.
Popup {
    id: root

    // Wider than it was, because the text is no longer allowed to run off the
    // end: the width is what decides how often a task needs a second line.
    readonly property int bodyWidth: 300
    readonly property int rowPad: 4
    // The head of a row: the dot, and the air between it and the text.
    readonly property int gutter: 16
    // A fixed column, so the dates line up down the right edge instead of
    // ending wherever each one happens to.
    readonly property int dayWidth: 46
    readonly property int dotSize: 6

    // Enough of a list to read at a glance. Past it the popup says how many
    // more there are, which is the honest answer — a bar popup is not where
    // eighty tasks get worked through.
    readonly property int cap: 9

    // A row is never shorter than a single line's worth of row.
    readonly property int rowMin: 20

    spacing: 3

    readonly property var rows: Tasks.ordered

    // Future-dated tasks also keep the list open, even with a zero bar count.
    function complete(task): void {
        Tasks.complete(task);
        if (Tasks.ordered.length === 0)
            OpenPopup.close(root.anchorItem);
    }

    function dotColour(task) {
        switch (Tasks.urgency(task)) {
        case "late":
            return Theme.taskLate;
        case "now":
            return Theme.taskToday;
        case "soon":
            return Theme.taskSoon;
        }
        return Theme.taskUndated;
    }

    // Put back what was just ticked off, and add something: the plus at the
    // right end, where every popup under the bar keeps it. Undo only appears
    // for the ten seconds after a tick (Tasks.undoable), so it is never
    // sitting there offering to undo something from this morning, and it is
    // needed, because the whole row is a target.
    PopupHeader {
        width: root.bodyWidth
        title: "Tasks"
        addable: Tasks.loaded
        onAdd: Launcher.openWith(Launcher.taskPrefix)

        Repeater {
            model: Object.keys(Tasks.undoable)

            delegate: PopupButton {
                required property string modelData

                framed: true
                glyph: Theme.glyph.undo
                label: "undo"
                onTapped: Tasks.restore(Tasks.undoable[modelData].task)
            }
        }

        ReconnectButton {}

        RetryButton { service: Tasks }

    }

    // What went wrong since the list loaded. Before that, the line below
    // says it in place of the list.
    PopupText {
        width: root.bodyWidth
        leftPadding: 6
        visible: Tasks.loaded && Tasks.trouble !== "" && Tasks.trouble !== Google.reconnect
        text: Tasks.trouble
        color: Theme.warn
        font.pixelSize: Theme.footnoteSize
        opacity: 0.8
        elide: Text.ElideRight
    }

    PopupText {
        width: root.bodyWidth
        visible: !Tasks.loaded || root.rows.length === 0
        text: !Tasks.loaded ? (Tasks.trouble !== "" ? Tasks.trouble : "Connecting…") : "Nothing on the list"
        color: Theme.label2
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: root.rows.slice(0, root.cap)

        delegate: PopupRow {
            id: row

            required property var modelData

            width: root.bodyWidth
            // As tall as the text it holds, never shorter than a single line's
            // worth of row. The text is what decides, and the dot and the day
            // hang off its first line rather than off the row — a dot floating
            // halfway down a three-line task would read as belonging to the
            // middle line.
            height: Math.max(label.implicitHeight, root.rowMin) + root.rowPad * 2

            // The whole row completes it. On a list this tightly packed a
            // slipped press would otherwise tick off whatever it started on,
            // so only a release on the row counts.
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: root.complete(row.modelData)

            // Hung off the first line's baseline and sat a pixel over the
            // middle of its x-height, which is where that line looks like it
            // is. Centring on the line box instead put the dot a good two
            // pixels high, up level with the top of the capitals: the box has
            // to leave room under the baseline for descenders, and most rows
            // have none.
            //
            // It also grows a little under the pointer, which is the only
            // acknowledgement the row needs that clicking it will do something —
            // a tick appearing inside it would be drawing the outcome before it
            // happened.
            Rectangle {
                x: (root.gutter - width) / 2
                anchors.baseline: label.baseline
                anchors.baselineOffset: -(metrics.xHeight + height) / 2 - 1
                width: row.hovered ? root.dotSize + 2 : root.dotSize
                height: width
                radius: width / 2
                color: root.dotColour(row.modelData)

                Behavior on width {
                    NumberAnimation {
                        duration: Theme.selectMs
                        easing.type: Easing.OutCubic
                    }
                }
            }

            PopupText {
                id: label

                // The font's own measurements, for placing the dot against the
                // first line of a paragraph rather than the middle of it.
                FontMetrics {
                    id: metrics
                    font: label.font
                }

                x: root.gutter
                // Centred in the row rather than pinned to its top: a one-line
                // task is shorter than the row minimum, and left at the top it
                // sat with all the slack under it, hanging off the ceiling of
                // its own hover box. A wrapped row is exactly its text plus the
                // padding, so this comes back to rowPad there.
                y: Math.round((row.height - implicitHeight) / 2)
                width: root.bodyWidth - root.gutter - root.dayWidth - 6
                text: row.modelData.title
                font.pixelSize: Theme.captionSize
                opacity: 0.9
                wrapMode: Text.WordWrap
            }

            // The day, for anything further off than tomorrow. Today and
            // tomorrow are what the dot is already saying, and a date beside a
            // dot that means the same thing is the column this redesign took
            // out. When the account keeps more than one list, an undated task
            // says which list it is on instead — that is the only thing left
            // that distinguishes it.
            PopupText {
                anchors {
                    right: parent.right
                    rightMargin: 2
                    // The same line as the title's first, sat on the same
                    // baseline rather than at the same height — it is a size
                    // smaller, so matching tops would leave it riding high.
                    baseline: label.baseline
                }
                width: root.dayWidth
                horizontalAlignment: Text.AlignRight
                text: {
                    const day = Tasks.dayOf(row.modelData);
                    if (day === "")
                        return Tasks.lists.length > 1 ? row.modelData.listTitle : "";
                    if (day === Tasks.today || day === Tasks.tomorrow)
                        return "";
                    return Tasks.sayDay(day);
                }
                font.pixelSize: Theme.footnoteSize
                color: Tasks.urgency(row.modelData) === "late" ? Theme.warn : Theme.fg
                opacity: Tasks.urgency(row.modelData) === "late" ? 0.75 : 0.4
                elide: Text.ElideRight
            }
        }
    }

    PopupText {
        width: root.bodyWidth
        visible: root.rows.length > root.cap
        text: `    … and ${root.rows.length - root.cap} more`
        font.pixelSize: Theme.footnoteSize
        opacity: 0.45
    }
}

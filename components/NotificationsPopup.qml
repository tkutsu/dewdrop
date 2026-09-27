import QtQuick
import Quickshell
import qs
import qs.services

// The bell's popup: the last few notifications themselves, rather than a
// sentence counting them. Who sent it and what it said, newest at the top —
// the same two things the notice beside the clock showed as it went past.
//
// The newest few; the rest are in the centre, and the count line says so.
//
// A row is the notification, so clicking it does what clicking one does in
// the centre (Notifications.activate). The ✕ at its end, while the pointer is
// on it, puts it away without following it.
Popup {
    id: root

    readonly property int bodyWidth: 316
    readonly property int iconBox: 20
    readonly property int rowPad: 4
    // The text's inset from the edge of the row's highlight.
    readonly property int inset: 6
    readonly property int closeBox: 20
    readonly property var shown: Notifications.list.slice(0, 5)

    spacing: 2

    // The state line, when there is one worth saying: nothing at all, do not
    // disturb, or more waiting in the centre than are listed here.
    PopupText {
        readonly property int unlisted: Notifications.count - root.shown.length

        visible: text !== ""
        width: root.bodyWidth
        leftPadding: root.inset
        text: {
            const parts = [];
            if (Notifications.count === 0)
                parts.push("No notifications");
            else if (unlisted > 0)
                parts.push(`${unlisted} more in the centre`);
            if (Notifications.dnd)
                parts.push("do not disturb");
            return parts.join("  ·  ");
        }
        color: Theme.label2
    }

    Repeater {
        // Diffed by object, as in the centre: a plain array rebuilt every row
        // on each change, and the rebuilt rows left the hover (and the ✕, and
        // the next click) on whichever row now stood where the pointer had
        // been, rather than on the one under it.
        model: ScriptModel {
            values: root.shown
        }

        delegate: PopupRow {
            id: row

            required property var modelData

            width: root.bodyWidth
            height: lines.implicitHeight + root.rowPad * 2

            // Either way the row goes and the popup shrinks out from under the
            // pointer, so it holds open long enough to be reached again.
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: {
                root.hold(1500);
                Notifications.activate(row.modelData);
            }

            AppIcon {
                x: root.inset
                y: root.rowPad
                width: root.iconBox
                height: root.iconBox
                implicitHeight: root.iconBox
                windowClass: Notifications.keyOf(row.modelData)
                fallbackGlyph: Theme.glyph.notif
            }

            // Leaves room for the ✕ whether or not it is showing, so the text
            // does not rewrap as the pointer goes down the list.
            Column {
                id: lines

                x: root.inset + root.iconBox + 8
                y: root.rowPad
                width: row.width - x - root.closeBox - root.inset
                spacing: 1

                PopupText {
                    width: parent.width
                    text: Notifications.plain(row.modelData.summary) || row.modelData.appName
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                PopupText {
                    width: parent.width
                    visible: text !== ""
                    text: Notifications.plain(row.modelData.body)
                    color: Theme.label2
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            PopupButton {
                anchors.right: parent.right
                y: root.rowPad
                width: root.closeBox
                height: root.iconBox
                visible: row.hovered
                glyph: Theme.glyph.close
                glyphSize: Theme.captionSize
                onTapped: {
                    root.hold(1500);
                    row.modelData.dismiss();
                }
            }
        }
    }
}

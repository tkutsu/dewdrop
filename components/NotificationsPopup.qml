import QtQuick
import qs
import qs.services

// The bell's popup: the last few notifications themselves, rather than a
// sentence counting them. Who sent it and what it said, newest at the top —
// the same two things the notice beside the clock showed as it went past.
//
// The newest few; the rest are in the centre, and the count line says so.
Popup {
    id: root

    readonly property int rowWidth: 300
    readonly property int iconBox: 20
    readonly property var shown: Notifications.list.slice(0, 5)

    padding: 8

    Column {
        spacing: 8

        // The state line, when there is one worth saying: nothing at all, do
        // not disturb, or more waiting in the centre than are listed here.
        PopupText {
            readonly property int unlisted: Notifications.count - root.shown.length

            visible: text !== ""
            width: root.rowWidth
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
            model: root.shown

            delegate: Row {
                id: row

                required property var modelData

                spacing: 8

                AppIcon {
                    width: root.iconBox
                    height: root.iconBox
                    implicitHeight: root.iconBox
                    windowClass: Notifications.keyOf(row.modelData)
                    fallbackGlyph: Theme.glyph.notif
                }

                Column {
                    width: root.rowWidth - root.iconBox - row.spacing
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
            }
        }
    }
}

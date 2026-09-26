import QtQuick
import qs
import qs.components
import qs.services

// Unread mail: who, what about, and when, newest first. A click on a row
// opens it in place to be read; a click on the text it opens onto takes the
// thread to the Gmail app. The foot answers the open mail — reply and reply
// to all, as a compose window filled in for it — and writes a new one.
//
// Two lines a row, the way Gmail's list reads: the sender and the time, then
// the subject with as much of the opening as fits after it. Nothing wraps; a
// mail is opened to be read, and the row only has to say which one it is.
Popup {
    id: root

    readonly property int bodyWidth: 320
    readonly property int rowTextSize: Theme.popupTextSize - 1
    readonly property int rowPad: 4
    // The text's inset from the edge of the row's highlight.
    readonly property int inset: 6
    // A fixed column, so the times line up down the right edge.
    readonly property int whenWidth: 44
    readonly property int cap: 8
    readonly property int footHeight: 20

    readonly property var rows: Email.threads.slice(0, root.cap)

    // The thread opened in place, by id, and its row while it is still on
    // the list. One at a time: two open mails would be a page, not a popup.
    property string expanded: ""
    readonly property var openRow: root.rows.find(r => r.id === root.expanded) ?? null
    // How tall an open mail may get before it scrolls.
    readonly property int bodyMax: 240

    spacing: 3

    PopupText {
        width: root.bodyWidth
        leftPadding: root.inset
        visible: !Email.loaded || Email.total === 0
        text: !Email.loaded ? Email.tooltip : "No unread mail"
        color: Theme.label2
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: root.rows

        delegate: PopupRow {
            id: row

            required property var modelData

            width: root.bodyWidth
            readonly property bool isOpen: root.expanded === row.modelData.id

            height: lines.implicitHeight + root.rowPad * 2

            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: {
                if (row.isOpen) {
                    root.expanded = "";
                } else {
                    root.expanded = row.modelData.id;
                    Email.read(row.modelData);
                }
            }

            Column {
                id: lines

                x: root.inset
                y: root.rowPad
                width: row.width - root.inset * 2
                spacing: 1

                Item {
                    width: parent.width
                    height: from.implicitHeight

                    PopupText {
                        id: from
                        width: parent.width - root.whenWidth
                        text: row.modelData.from
                        font.pixelSize: root.rowTextSize
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    PopupText {
                        anchors.right: parent.right
                        anchors.baseline: from.baseline
                        text: Email.sayWhen(row.modelData.at)
                        font.pixelSize: root.rowTextSize - 1
                        color: Theme.label2
                    }
                }

                // The subject takes what it needs and the snippet what is left,
                // so a short subject shows more of the mail and a long one
                // pushes the snippet off the end rather than being cut itself.
                Row {
                    width: parent.width

                    PopupText {
                        id: subject
                        width: Math.min(implicitWidth, parent.width)
                        text: row.modelData.subject
                        font.pixelSize: root.rowTextSize
                        color: Theme.label
                        elide: Text.ElideRight
                    }

                    PopupText {
                        width: parent.width - subject.width
                        visible: !row.isOpen && width > 30 && text !== ""
                        leftPadding: 6
                        text: row.modelData.snippet
                        font.pixelSize: root.rowTextSize
                        color: Theme.label2
                        elide: Text.ElideRight
                    }
                }

                // The mail itself, once the row is open. The snippet stands in,
                // faintly, until the text lands. Scrolls past bodyMax rather
                // than growing the popup down the screen; a click on it takes
                // the thread to the Gmail app, which is where a mail too long
                // for this goes anyway.
                Flickable {
                    visible: row.isOpen
                    width: parent.width
                    height: visible ? Math.min(body.implicitHeight, root.bodyMax) + 6 : 0
                    topMargin: 6
                    contentHeight: body.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    PopupText {
                        id: body

                        readonly property var fetched: Email.bodies[row.modelData.message]

                        width: parent.width
                        text: body.fetched !== undefined ? body.fetched : row.modelData.snippet + "…"
                        font.pixelSize: root.rowTextSize
                        color: body.fetched !== undefined ? Theme.label : Theme.label3
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText

                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: Email.open(row.modelData)
                        }
                    }
                }
            }
        }
    }

    PopupText {
        width: root.bodyWidth
        leftPadding: root.inset
        visible: Email.loaded && Email.total > root.rows.length && root.rows.length > 0
        text: `… and ${Email.total - root.rows.length} more`
        font.pixelSize: root.rowTextSize - 1
        opacity: 0.45
    }

    Rectangle {
        width: root.bodyWidth
        height: Theme.pillBorder
        color: Theme.stroke
    }

    // The foot: the open mail's two answers at the left, a new mail at the
    // right end, where every popup under the bar keeps its plus, and what went
    // wrong, if anything, between them.
    Item {
        width: root.bodyWidth
        height: root.footHeight + 2

        Row {
            id: answers

            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            visible: root.openRow !== null

            PopupButton {
                height: root.footHeight
                framed: true
                glyph: Theme.glyph.reply
                label: "reply"
                glyphSize: Theme.popupTextSize - 1
                textSize: root.rowTextSize - 1
                onTapped: Email.reply(root.openRow, false)
            }

            PopupButton {
                height: root.footHeight
                framed: true
                glyph: Theme.glyph.replyAll
                label: "reply all"
                glyphSize: Theme.popupTextSize - 1
                textSize: root.rowTextSize - 1
                onTapped: Email.reply(root.openRow, true)
            }
        }

        PopupText {
            anchors.right: add.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: Email.trouble
            visible: Email.loaded && Email.trouble !== "" && !answers.visible
            color: Theme.warn
            font.pixelSize: root.rowTextSize - 1
            opacity: 0.8
            elide: Text.ElideRight
            width: Math.min(implicitWidth, root.bodyWidth - 60)
        }

        PopupButton {
            id: add

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: root.footHeight
            height: root.footHeight
            framed: true
            glyph: Theme.glyph.plus
            glyphSize: Theme.popupTextSize - 1
            onTapped: Email.compose({})
        }
    }
}

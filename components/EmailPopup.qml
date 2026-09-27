import QtQuick
import qs
import qs.components
import qs.services

// Unread mail: who, what about, and when, newest first. A click on a row
// opens it in place to be read, and the foot then has the two things to do
// with it: open the thread in the Gmail app, or mark it read. The plus at the
// foot's right end writes a new one.
//
// Two lines a row, the way Gmail's list reads: the sender and the time, then
// the subject with as much of the opening as fits after it. Nothing wraps; a
// mail is opened to be read, and the row only has to say which one it is.
Popup {
    id: root

    readonly property int bodyWidth: 320
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

    // How much the open mails add to the rows right now, mid-animation
    // included — the one open and the one closing, when you move from one to
    // the next.
    readonly property real grown: {
        let g = 0;
        for (let i = 0; i < list.count; i++)
            g += list.itemAt(i)?.grown ?? 0;
        return g;
    }

    // The window is held at the height of a fully open mail, so a row opening
    // grows the box inside it rather than resizing the popup every frame of
    // the animation (see Popup.reserveHeight).
    reserveHeight: chromeHeight - grown + bodyMax + 6

    // The text of every row on show, asked for as the popup opens, so a row
    // opens straight to its full height instead of to the snippet and then
    // again when the text lands. Each is read once a session.
    Component.onCompleted: {
        for (const r of root.rows)
            Email.read(r);
    }

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
        id: list

        model: root.rows

        delegate: PopupRow {
            id: row

            required property var modelData

            width: root.bodyWidth
            readonly property bool isOpen: root.expanded === row.modelData.id
            readonly property real grown: reveal.height

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
                        font.pixelSize: Theme.captionSize
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    PopupText {
                        anchors.right: parent.right
                        anchors.baseline: from.baseline
                        text: Email.sayWhen(row.modelData.at)
                        font.pixelSize: Theme.footnoteSize
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
                        font.pixelSize: Theme.captionSize
                        color: Theme.label
                        elide: Text.ElideRight
                    }

                    PopupText {
                        width: parent.width - subject.width
                        visible: !row.isOpen && width > 30 && text !== ""
                        leftPadding: 6
                        text: row.modelData.snippet
                        font.pixelSize: Theme.captionSize
                        color: Theme.label2
                        elide: Text.ElideRight
                    }
                }

                // The mail itself, once the row is open, unrolling downwards
                // from under the subject. The snippet stands in, faintly, if
                // the text has not landed yet, and the height follows it when
                // it does rather than jumping. Scrolls past bodyMax rather than
                // growing the popup down the screen.
                Flickable {
                    id: reveal

                    visible: height > 0
                    width: parent.width
                    height: row.isOpen ? Math.min(body.implicitHeight, root.bodyMax) + 6 : 0
                    topMargin: 6
                    contentHeight: body.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Behavior on height {
                        NumberAnimation {
                            duration: Theme.foldMs
                            easing.type: Easing.InOutCubic
                        }
                    }

                    PopupText {
                        id: body

                        readonly property var fetched: Email.bodies[row.modelData.message]

                        width: parent.width
                        text: body.fetched !== undefined ? body.fetched : row.modelData.snippet + "…"
                        font.pixelSize: Theme.captionSize
                        color: body.fetched !== undefined ? Theme.label : Theme.label3
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
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
        font.pixelSize: Theme.footnoteSize
        opacity: 0.45
    }

    Rectangle {
        width: root.bodyWidth
        height: Theme.pillBorder
        color: Theme.stroke
    }

    // The foot: the open mail's two actions at the left, a new mail at the
    // right end, where every popup under the bar keeps its plus, and what went
    // wrong, if anything, between them.
    Item {
        width: root.bodyWidth
        height: root.footHeight + 2

        Row {
            id: actions

            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            visible: root.openRow !== null

            PopupButton {
                height: root.footHeight
                framed: true
                glyph: Theme.glyph.openApp
                label: "open"
                glyphSize: Theme.captionSize
                textSize: Theme.footnoteSize
                onTapped: Email.open(root.openRow)
            }

            PopupButton {
                height: root.footHeight
                framed: true
                glyph: Theme.glyph.mailRead
                label: "mark read"
                glyphSize: Theme.captionSize
                textSize: Theme.footnoteSize
                // The row goes, the box shrinks, and the pointer is left
                // below it; a moment's grace to bring it back to the list.
                onTapped: {
                    root.hold(1500);
                    Email.markRead(root.openRow);
                }
            }
        }

        PopupText {
            anchors.right: ends.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: Email.trouble
            visible: Email.trouble !== "" && Email.trouble !== Google.reconnect && !actions.visible
            color: Theme.warn
            font.pixelSize: Theme.footnoteSize
            opacity: 0.8
            elide: Text.ElideRight
            width: Math.min(implicitWidth, parent.width - ends.width - 8)
        }

        Row {
            id: ends

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            ReconnectButton {
                height: root.footHeight
                textSize: Theme.footnoteSize
            }

            PopupButton {
                width: root.footHeight
                height: root.footHeight
                framed: true
                glyph: Theme.glyph.plus
                glyphSize: Theme.captionSize
                onTapped: Email.compose()
            }
        }
    }
}

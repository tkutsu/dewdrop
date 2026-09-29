import QtQuick
import qs
import qs.components
import qs.services

// Unread mail: who, what about, and when, newest first. A click on a row
// opens it in place to be read, and the two things to do with it come up in
// its top line: open the thread in the Gmail app, or mark it read. The plus at the header's
// right end writes a new one.
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

    readonly property var rows: Email.threads.slice(0, root.cap)

    // The thread opened in place, by id. One at a time: two open mails would
    // be a page, not a popup.
    property string expanded: ""
    // How tall an open mail may get before it scrolls.
    readonly property int bodyMax: 240
    // The gutter an open thread's rail runs down, when it has several mails.
    readonly property int railWidth: 12

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
    reserveHeight: chromeHeight - grown + bodyMax + 12

    // The text of every row on show, asked for as the popup opens, so a row
    // opens straight to its full height instead of to the snippet and then
    // again when the text lands. Each is read once a session.
    Component.onCompleted: {
        for (const r of root.rows)
            Email.read(r);
    }

    spacing: 3

    // Gmail itself, and a new mail at the right end, where every popup under
    // the bar keeps its plus.
    PopupHeader {
        width: root.bodyWidth
        title: "Mail"

        ReconnectButton {}

        PopupButton {
            framed: true
            glyph: Theme.glyph.openApp
            label: "inbox"
            onTapped: {
                OpenPopup.dismiss();
                Email.openInbox();
            }
        }

        PopupButton {
            framed: true
            glyph: Theme.glyph.plus
            onTapped: Email.compose("")
        }
    }

    // What went wrong since the list loaded. Before that, the line below
    // says it in place of the list.
    PopupText {
        width: root.bodyWidth
        leftPadding: root.inset
        visible: Email.loaded && Email.trouble !== "" && Email.trouble !== Google.reconnect
        text: Email.trouble
        color: Theme.warn
        font.pixelSize: Theme.footnoteSize
        opacity: 0.8
        elide: Text.ElideRight
    }

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
                        width: Math.min(implicitWidth, parent.width - root.whenWidth - (row.isOpen ? mailActions.width + 6 : 0) - count.width)
                        text: row.modelData.from
                        font.pixelSize: Theme.captionSize
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    // How many are waiting in the thread, the way Gmail's
                    // list counts a conversation, when it is more than one.
                    PopupText {
                        id: count
                        anchors.left: from.right
                        anchors.baseline: from.baseline
                        width: visible ? implicitWidth : 0
                        visible: row.modelData.messages.length > 1
                        leftPadding: 5
                        text: row.modelData.messages.length
                        font.pixelSize: Theme.footnoteSize
                        color: Theme.label2
                    }

                    // The two things to do with an open mail, between the
                    // sender and the time. Centred on the line and a little
                    // taller than it, into the row's padding, so they come and
                    // go without moving anything.
                    Row {
                        id: mailActions

                        anchors.right: parent.right
                        anchors.rightMargin: root.whenWidth
                        anchors.verticalCenter: from.verticalCenter
                        spacing: 4
                        opacity: row.isOpen ? 1 : 0
                        visible: opacity > 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.foldMs
                                easing.type: Easing.InOutCubic
                            }
                        }

                        PopupButton {
                            framed: true
                            glyph: Theme.glyph.openApp
                            label: "open"
                            onTapped: Email.open(row.modelData)
                        }

                        PopupButton {
                            framed: true
                            glyph: Theme.glyph.mailRead
                            label: "mark read"
                            onTapped: Email.markRead(row.modelData)
                        }
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
                //
                // One mail is its text alone. Several unread in the thread are
                // each under who sent it and when, oldest first, strung on a
                // rail down the left: a dot at each sender, and a line from one
                // to the next.
                Item {
                    id: reveal

                    visible: height > 0
                    width: parent.width
                    height: row.isOpen ? mail.height + 12 : 0
                    clip: true

                    Behavior on height {
                        NumberAnimation {
                            duration: Theme.foldMs
                            easing.type: Easing.InOutCubic
                        }
                    }

                    Flickable {
                        id: mail

                        y: 6
                        width: parent.width
                        height: Math.min(chain.implicitHeight, root.bodyMax)
                        contentHeight: chain.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: chain

                            readonly property int links: row.modelData.messages.length

                            width: parent.width
                            spacing: 10

                            Repeater {
                                model: row.modelData.messages

                                delegate: Item {
                                    id: link

                                    required property var modelData
                                    required property int index
                                    readonly property bool chained: chain.links > 1
                                    readonly property var fetched: Email.bodies[link.modelData.id]

                                    width: chain.width
                                    height: said.implicitHeight

                                    // Down to the next dot, clear of both.
                                    Rectangle {
                                        visible: link.chained && link.index < chain.links - 1
                                        x: dot.x + Math.floor(dot.width / 2)
                                        y: dot.y + dot.height + 3
                                        width: 1
                                        height: link.height + chain.spacing - dot.height - 6
                                        color: Theme.label3
                                    }

                                    Rectangle {
                                        id: dot

                                        visible: link.chained
                                        // On whole pixels, or a dot this small blurs.
                                        x: Math.floor((root.railWidth - width) / 2)
                                        y: Math.round((sender.height - height) / 2)
                                        width: 5
                                        height: 5
                                        radius: width / 2
                                        color: Theme.label2
                                    }

                                    Column {
                                        id: said

                                        x: link.chained ? root.railWidth : 0
                                        width: link.width - x
                                        spacing: 2

                                        Item {
                                            visible: link.chained
                                            width: parent.width
                                            height: sender.implicitHeight

                                            PopupText {
                                                id: sender
                                                width: parent.width - root.whenWidth
                                                text: link.modelData.from
                                                font.pixelSize: Theme.footnoteSize
                                                font.weight: Font.DemiBold
                                                color: Theme.label2
                                                elide: Text.ElideRight
                                            }

                                            PopupText {
                                                anchors.right: parent.right
                                                anchors.baseline: sender.baseline
                                                text: Email.sayWhen(link.modelData.at)
                                                font.pixelSize: Theme.footnoteSize
                                                color: Theme.label3
                                            }
                                        }

                                        PopupText {
                                            width: parent.width
                                            text: link.fetched !== undefined ? link.fetched : link.modelData.snippet + "…"
                                            font.pixelSize: Theme.captionSize
                                            color: link.fetched !== undefined ? Theme.label : Theme.label3
                                            wrapMode: Text.Wrap
                                            textFormat: Text.PlainText
                                        }
                                    }
                                }
                            }
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
        font.pixelSize: Theme.footnoteSize
        opacity: 0.45
    }
}

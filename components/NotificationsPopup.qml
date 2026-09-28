import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets
import qs
import qs.services

// The bell's popup, which is the notification centre: everything being kept,
// newest first, with do not disturb and clear in its header. It used to be a
// few rows and a button through to the centre, a column of glass cards down
// the right edge of the screen; the two were one list said twice, so the
// centre moved in here.
//
// Grouped by sender, the way swaync did it: an app with several waiting is
// one card with the rest stacked behind it, opened with a click to pick one
// out, and cleared with one click on its ✕ rather than one per notification.
//
// Clicking a card does what clicking the notice beside the clock does
// (Notifications.activate). While the pointer is on a card, a ✕ stands where
// the sender's icon was and puts it away without following it.
Popup {
    id: root

    readonly property int bodyWidth: 340
    // The text's inset from the edge of the popup, as the other popups keep it.
    readonly property int inset: 6
    readonly property int cardPad: 10
    // A card is a fill inside the popup's box, two steps rounder than a row's
    // highlight since it is taller than one.
    readonly property int cardRadius: Theme.selectionRadius + 2
    readonly property int cardGap: 6
    readonly property int iconSize: 32
    readonly property int iconRadius: 6
    // The sender's picture, when it sent one: a contact, a sleeve, a
    // screenshot. Square on the right of the card, as the system shows it.
    readonly property int thumbSize: 40
    // The cards stacked behind a closed group: how far each one shows below
    // the card in front of it, and how much narrower it is on each side.
    readonly property int sheetPeek: 4
    readonly property int sheetInset: 8
    // How tall the list gets before it scrolls: two thirds of the screen,
    // which leaves the popup a popup rather than a panel down the side.
    readonly property int listMax: Math.round((root.screen?.height ?? 1080) * 2 / 3)

    spacing: 6

    // Opened on a notice, the popup marks it until it closes (see
    // Notifications.focusOn).
    Component.onDestruction: Notifications.centreFocus = null

    // --- groups ---------------------------------------------------------------
    // By the name the card shows, so what is grouped is what reads as the
    // same sender.
    function groupOf(n) {
        return n?.appName || "Notification";
    }

    // The senders, in the order of their newest notification. Names rather
    // than arrays of notifications, so the list's model diffs them by value
    // and a group keeps its card (and whether it is open) as it changes.
    readonly property var groups: {
        const keys = [];
        for (const n of Notifications.list) {
            const key = root.groupOf(n);
            if (!keys.includes(key))
                keys.push(key);
        }
        return keys;
    }

    // Bring the notification asked for into view: on opening, once the cards
    // exist, and again if another notice is picked while the popup is up.
    function showFocus() {
        const focus = Notifications.centreFocus;
        const at = focus ? root.groups.indexOf(root.groupOf(focus)) : -1;
        if (at >= 0)
            cards.positionViewAtIndex(at, ListView.Contain);
    }

    Connections {
        target: Notifications

        function onCentreFocusChanged(): void {
            Qt.callLater(root.showFocus);
        }
    }

    // The time the ages are written against. On the minute, like the clock:
    // "now" becoming "1m" is the finest step shown.
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // --- header ---------------------------------------------------------------
    Item {
        width: root.bodyWidth
        height: 22

        PopupText {
            x: root.inset
            anchors.verticalCenter: parent.verticalCenter
            text: "Notifications"
            font.weight: Font.DemiBold
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            PopupButton {
                framed: true
                lit: Notifications.dnd
                glyph: Theme.glyph.dnd
                label: "do not disturb"
                glyphSize: Theme.captionSize
                onTapped: Notifications.setDnd(!Notifications.dnd)
            }

            PopupButton {
                visible: Notifications.count > 0
                framed: true
                label: "clear"
                onTapped: Notifications.clearAll()
            }
        }
    }

    // Nothing waiting: a line saying so, rather than a header over nothing.
    PopupText {
        visible: Notifications.count === 0
        width: root.bodyWidth
        leftPadding: root.inset
        bottomPadding: 2
        text: "No notifications"
        color: Theme.label2
    }

    // --- the cards --------------------------------------------------------------
    ListView {
        id: cards

        visible: count > 0
        width: root.bodyWidth
        height: Math.min(contentHeight, root.listMax)
        interactive: contentHeight > height
        clip: true
        spacing: root.cardGap
        boundsBehavior: Flickable.StopAtBounds

        // Through a ScriptModel rather than the array itself: the array is
        // rebuilt on every change, and handed straight to the view that tore
        // down every card and built it again per arrival — and once per
        // notification on Clear. The model diffs by value, so only the group
        // that came or went is touched and the others keep their place.
        model: ScriptModel {
            values: root.groups
        }

        // A group arriving or leaving slides the ones below it rather than
        // jumping them.
        displaced: Transition {
            NumberAnimation {
                property: "y"
                duration: Theme.fadeMs
                easing.type: Easing.OutCubic
            }
        }

        delegate: Group {}

        // Once the cards exist rather than now, since the list is built in the
        // same pass as this.
        Component.onCompleted: Qt.callLater(root.showFocus)
    }

    // Everything one sender has waiting. Closed, it is its newest card with
    // the rest stacked behind it; open, a header and every card under it.
    component Group: Column {
        id: group

        required property string modelData
        readonly property var items: Notifications.list.filter(n => root.groupOf(n) === group.modelData)
        // Closed until asked, unless the popup was opened on one of these:
        // that one is what was asked for, and it should be in plain sight.
        property bool open: group.items.includes(Notifications.centreFocus)
        readonly property bool stacked: group.items.length > 1 && !group.open

        // Down to one, it is a card like any other, and it closes so that the
        // next to arrive stacks on it rather than finding it open.
        onItemsChanged: if (group.items.length < 2)
            group.open = false

        width: ListView.view.width
        spacing: root.cardGap

        // A card leaving an open group slides the ones below it up, as the
        // list does.
        move: Transition {
            NumberAnimation {
                property: "y"
                duration: Theme.fadeMs
                easing.type: Easing.OutCubic
            }
        }

        // Open: whose these are, and the two things that act on all of them.
        Item {
            width: parent.width
            height: 22
            visible: group.open && group.items.length > 1

            PopupText {
                x: root.inset
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - groupButtons.width - 8
                text: group.modelData
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Row {
                id: groupButtons

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                PopupButton {
                    framed: true
                    label: "show less"
                    onTapped: group.open = false
                }

                PopupButton {
                    framed: true
                    label: "clear"
                    onTapped: group.items.forEach(n => n.dismiss())
                }
            }
        }

        Repeater {
            model: ScriptModel {
                values: group.stacked ? group.items.slice(0, 1) : group.items
            }

            delegate: Card {
                behind: group.stacked ? group.items.slice(1) : []
                onOpened: group.open = true
            }
        }
    }

    // One notification.
    component Card: Item {
        id: card

        required property var modelData
        readonly property Notification n: modelData
        // The rest of its group, stacked behind it while the group is closed.
        // Then a click opens the group rather than following this one, and
        // the ✕ clears all of them.
        property var behind: []
        readonly property int sheets: Math.min(card.behind.length, 2)
        signal opened
        readonly property var buttons: Notifications.buttons(card.n)
        readonly property string icon: Notifications.iconFor(card.n)
        // A picture of its own — a contact, a sleeve, a screenshot. Not the
        // sender's icon again: a sender that names only an icon gets it
        // handed back here as the image too, and the card would show the same
        // logo at both ends.
        readonly property string image: {
            const url = card.n ? Notifications.url(card.n.image) : "";
            return url.startsWith("image://icon/") || url === card.icon ? "" : url;
        }

        width: parent.width
        height: fill.height + card.sheets * root.sheetPeek

        HoverHandler {
            id: hover
        }

        // The cards behind, each only the strip of it that shows below the
        // one in front. Clipped to that strip rather than drawn whole behind:
        // the fills are translucent, and a whole card behind would lighten
        // the one in front of it.
        Repeater {
            model: card.sheets

            delegate: Item {
                required property int index

                x: root.sheetInset * (index + 1)
                y: fill.height + root.sheetPeek * index
                width: card.width - x * 2
                height: root.sheetPeek
                clip: true

                Rectangle {
                    y: root.sheetPeek - height
                    width: parent.width
                    height: root.cardRadius * 2
                    radius: root.cardRadius
                    color: Theme.selection
                    opacity: 0.5
                }
            }
        }

        // The card: a faint fill at rest, the row highlight under the
        // pointer, and one step past it on the one the popup was opened on,
        // which is how it says "this one" among the rest.
        Rectangle {
            id: fill

            readonly property bool focused: card.n && card.n === Notifications.centreFocus

            width: parent.width
            height: content.implicitHeight + root.cardPad * 2
            radius: root.cardRadius
            color: fill.focused ? Theme.selectionStrong : Theme.selection
            opacity: fill.focused || hover.hovered ? 1 : 0.5

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.fadeMs
                }
            }
        }

        // Clicking the card is asking for what it is about (see
        // Notifications.activate), or, on a stack, which of them.
        MouseArea {
            anchors.fill: parent
            onClicked: card.behind.length > 0 ? card.opened() : Notifications.activate(card.n)
        }

        Item {
            id: content

            x: root.cardPad
            y: root.cardPad
            width: parent.width - root.cardPad * 2
            implicitHeight: Math.max(iconBox.height, text.implicitHeight, thumb.visible ? thumb.height : 0)

            // The app's icon, or a bell on a tile when it sent none; under the
            // pointer, the ✕ in its place.
            Item {
                id: iconBox

                width: root.iconSize
                height: root.iconSize

                IconImage {
                    id: appIcon

                    anchors.fill: parent
                    source: card.icon
                    visible: status === Image.Ready && !hover.hovered
                }

                Rectangle {
                    anchors.fill: parent
                    visible: appIcon.status !== Image.Ready && !hover.hovered
                    radius: root.iconRadius
                    color: Theme.selection

                    Glyph {
                        anchors.centerIn: parent
                        text: Theme.glyph.notif
                        fontSize: Theme.glyphSizeLarge
                        color: Theme.label2
                    }
                }

                PopupButton {
                    anchors.fill: parent
                    visible: hover.hovered
                    glyph: Theme.glyph.close
                    glyphSize: Theme.labelSize
                    onTapped: [card.n, ...card.behind].forEach(n => n.dismiss())
                }
            }

            Column {
                id: text

                x: iconBox.width + 10
                width: content.width - x - (thumb.visible ? thumb.width + 10 : 0)
                spacing: 2

                // Who, and how long ago, on one line.
                Item {
                    width: parent.width
                    height: appName.implicitHeight

                    PopupText {
                        id: appName

                        width: parent.width - age.implicitWidth - 8
                        text: (card.n?.appName || "Notification") + (card.behind.length > 0 ? `  ·  ${card.behind.length + 1}` : "")
                        color: Theme.label2
                        font.pixelSize: Theme.captionSize
                        elide: Text.ElideRight
                    }

                    PopupText {
                        id: age

                        anchors.right: parent.right
                        text: card.n ? Notifications.ago(card.n, clock.date.getTime()) : ""
                        color: Theme.label3
                        font.pixelSize: Theme.captionSize
                    }
                }

                PopupText {
                    width: parent.width
                    visible: text !== ""
                    text: Notifications.plain(card.n?.summary)
                    color: card.n?.urgency === NotificationUrgency.Critical ? Theme.warn : Theme.label
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                PopupText {
                    width: parent.width
                    visible: text !== ""
                    text: Notifications.plain(card.n?.body)
                    color: Theme.label2
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    lineHeight: 1.1
                }

                // What the sender offers besides opening it: "Reply",
                // "Mark as read", "Show in folder".
                Flow {
                    width: parent.width
                    visible: card.buttons.length > 0
                    topPadding: 4
                    spacing: 4

                    Repeater {
                        model: card.buttons

                        delegate: PopupButton {
                            required property var modelData

                            framed: true
                            label: modelData.text
                            onTapped: Notifications.run(modelData)
                        }
                    }
                }
            }

            ClippingRectangle {
                id: thumb

                anchors.right: parent.right
                width: root.thumbSize
                height: root.thumbSize
                radius: root.iconRadius
                color: "transparent"
                visible: card.image !== "" && picture.status === Image.Ready

                Image {
                    id: picture

                    anchors.fill: parent
                    source: card.image
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: root.thumbSize * 2
                    sourceSize.height: root.thumbSize * 2
                    asynchronous: true
                }
            }
        }
    }
}

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
// one card with a count badge, opened with a click to pick one
// out, and cleared with one click on its ✕ rather than one per notification.
//
// Clicking a card does what clicking the notice beside the clock does
// (Notifications.activate). While the pointer is on a card, a ✕ stands where
// the time was and puts it away without following it.
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

    // Keep the centre available until the last notification is cleared.
    function clear(items): void {
        for (const n of items)
            n.dismiss();
        if (Notifications.count === 0)
            OpenPopup.close(root.anchorItem);
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

    PopupHeader {
        width: root.bodyWidth
        title: "Notifications"

        PopupButton {
            framed: true
            lit: Notifications.dnd
            glyph: Theme.glyph.dnd
            label: "do not disturb"
            onTapped: Notifications.setDnd(!Notifications.dnd)
        }

        PopupButton {
            visible: Notifications.count > 0
            framed: true
            label: "clear"
            onTapped: root.clear(Notifications.list)
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
    // a count badge; open, a header and every card under it.
    // Card positions change immediately with the group's height: animating
    // them clips the last card when the header and viewport shrink.
    component Group: Column {
        id: group

        required property string modelData
        readonly property var items: Notifications.list.filter(n => root.groupOf(n) === group.modelData)
        // Closed until asked, unless the popup was opened on one of these:
        // that one is what was asked for, and it should be in plain sight.
        property bool open: false
        Component.onCompleted: group.open = group.items.includes(Notifications.centreFocus)
        Connections {
            target: Notifications
            function onCentreFocusChanged(): void {
                if (group.items.includes(Notifications.centreFocus))
                    group.open = true;
            }
        }
        readonly property bool collapsed: group.items.length > 1 && !group.open

        // Down to one, it is a card like any other, and it closes so that the
        // next to arrive joins a collapsed group rather than finding it open.
        onItemsChanged: if (group.items.length < 2)
            group.open = false

        width: ListView.view.width
        spacing: root.cardGap

        // Open: whose these are, and the two things that act on all of them.
        PopupHeader {
            width: parent.width
            visible: group.open && group.items.length > 1
            title: group.modelData

            PopupButton {
                framed: true
                label: "show less"
                onTapped: group.open = false
            }

            PopupButton {
                framed: true
                label: "clear"
                onTapped: root.clear(group.items)
            }
        }

        Repeater {
            model: ScriptModel {
                values: group.collapsed ? group.items.slice(0, 1) : group.items
            }

            delegate: Card {
                others: group.collapsed ? group.items.slice(1) : []
                onOpened: group.open = true
            }
        }
    }

    // One notification.
    component Card: Item {
        id: card

        required property var modelData
        readonly property Notification n: modelData
        // The rest of its group, counted in the badge while the group is closed.
        // Then a click opens the group rather than following this one, and
        // the ✕ clears all of them.
        property var others: []
        signal opened
        readonly property var buttons: Notifications.buttons(card.n)
        readonly property string icon: Notifications.iconFor(card.n)
        // Mullvad's image payload is its logo, not a preview. Icon URLs and
        // images matching the sender's icon likewise belong only on the left.
        readonly property string image: {
            if (!card.n || card.n.desktopEntry === "mullvad-vpn" || card.n.appName === "Mullvad VPN")
                return "";
            const url = Notifications.url(card.n.image);
            return url.startsWith("image://icon/") || url === card.icon ? "" : url;
        }

        width: parent.width
        height: fill.height

        HoverHandler {
            id: hover
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
        // Notifications.activate), or, on a group, which of them.
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (card.others.length > 0) {
                    card.opened();
                } else {
                    Notifications.activate(card.n);
                    if (Notifications.count === 0)
                        OpenPopup.close(root.anchorItem);
                }
            }
        }

        Item {
            id: content

            x: root.cardPad
            y: root.cardPad
            width: parent.width - root.cardPad * 2
            implicitHeight: Math.max(iconBox.height, text.implicitHeight)

            // The app's icon, or a bell on a tile when it sent none.
            Item {
                id: iconBox

                width: root.iconSize
                height: root.iconSize

                IconImage {
                    id: appIcon

                    anchors.fill: parent
                    source: card.icon
                    visible: status === Image.Ready
                }

                Rectangle {
                    anchors.fill: parent
                    visible: appIcon.status !== Image.Ready
                    radius: root.iconRadius
                    color: Theme.selection

                    Glyph {
                        anchors.centerIn: parent
                        text: Theme.glyph.notif
                        fontSize: Theme.glyphSizeLarge
                        color: Theme.label2
                    }
                }

                Badge {
                    visible: card.others.length > 0
                    text: String(card.others.length + 1)
                    x: parent.width - width / 2
                    y: -height / 2
                }
            }

            Column {
                id: text

                x: iconBox.width + 10
                width: content.width - x
                spacing: 2

                // Who, and how long ago, on one line.
                Item {
                    id: metadata

                    width: parent.width
                    height: Math.max(appName.implicitHeight, dismiss.implicitHeight)

                    PopupText {
                        id: appName

                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Math.max(age.implicitWidth, dismiss.width) - 8
                        text: card.n?.appName || "Notification"
                        color: Theme.label2
                        font.pixelSize: Theme.captionSize
                        elide: Text.ElideRight
                    }

                    PopupText {
                        id: age

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !hover.hovered
                        text: card.n ? Notifications.ago(card.n, clock.date.getTime()) : ""
                        color: Theme.label3
                        font.pixelSize: Theme.captionSize
                    }

                    PopupButton {
                        id: dismiss

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: hover.hovered
                        glyph: Theme.glyph.close
                        glyphSize: Theme.captionSize
                        onTapped: root.clear([card.n, ...card.others])
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

                // A content image gets its own space below the text, keeping
                // the header aligned and preserving the whole image.
                Item {
                    width: parent.width
                    height: preview.height + 6
                    visible: card.image !== "" && picture.status === Image.Ready

                    ClippingRectangle {
                        id: preview

                        y: 6
                        width: parent.width
                        height: picture.implicitWidth > 0 ? Math.min(140, width * picture.implicitHeight / picture.implicitWidth) : 0
                        radius: root.iconRadius
                        color: "transparent"

                        Image {
                            id: picture

                            anchors.fill: parent
                            source: card.image
                            fillMode: Image.PreserveAspectFit
                            sourceSize.width: Math.ceil(preview.width * 2)
                            asynchronous: true
                        }
                    }
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
        }
    }
}

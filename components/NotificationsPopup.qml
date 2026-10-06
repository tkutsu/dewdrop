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
// A card shows all it says. Clicking it does what clicking the notice beside
// the clock does (Notifications.activate) and clears it; a closed group's card
// opens the group instead. While the pointer is on a card, a ✕ stands where
// the time was and clears it without following it.
Popup {
    id: root

    readonly property int bodyWidth: 453
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
    // Animate the cards inside a fixed window to avoid compositor repositioning.
    reserveHeight: root.chromeHeight - cards.height + root.listMax

    // Opened on a notice, the popup marks it until it closes (see
    // Notifications.focusOn).
    Component.onDestruction: Notifications.centreFocus = null

    // --- groups ---------------------------------------------------------------
    // One group open at a time; opened on a notice, its group starts open.
    property string expandedGroup: Notifications.centreFocus ? root.groupOf(Notifications.centreFocus) : ""

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
            root.expandedGroup = Notifications.centreFocus ? root.groupOf(Notifications.centreFocus) : "";
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
    component Group: Column {
        id: group

        required property string modelData
        readonly property var items: Notifications.list.filter(n => root.groupOf(n) === group.modelData)
        readonly property bool open: root.expandedGroup === group.modelData && group.items.length > 1
        readonly property bool collapsed: group.items.length > 1 && !group.open

        // Down to one, it is a card like any other, and it closes so that the
        // next to arrive joins a collapsed group rather than finding it open.
        onItemsChanged: if (group.items.length < 2 && root.expandedGroup === group.modelData)
            root.expandedGroup = ""

        width: ListView.view.width
        spacing: 0

        // The sender header collapses the group; its clear button dismisses it.
        Item {
            width: parent.width
            height: group.open ? groupHeader.height + root.cardGap : 0
            visible: height > 0
            clip: true

            Behavior on height {
                NumberAnimation {
                    duration: Theme.fadeMs
                    easing.type: Easing.InOutCubic
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.expandedGroup = ""
            }

            PopupHeader {
                id: groupHeader
                width: parent.width
                title: group.modelData

                PopupButton {
                    framed: true
                    label: "clear"
                    onTapped: root.clear(group.items)
                }
            }
        }

        Repeater {
            model: ScriptModel {
                values: group.items
            }

            // Retain hidden cards so closing can animate before they disappear.
            delegate: Item {
                id: slot
                required property var modelData
                required property int index
                readonly property bool shown: slot.index === 0 || !group.collapsed
                width: parent.width
                height: slot.shown ? notification.height + notification.y : 0
                visible: height > 0
                opacity: slot.shown ? 1 : 0
                clip: true

                Behavior on height {
                    enabled: slot.index > 0
                    NumberAnimation {
                        duration: Theme.fadeMs
                        easing.type: Easing.InOutCubic
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.fadeMs
                    }
                }

                Card {
                    id: notification
                    y: slot.index > 0 ? root.cardGap : 0
                    modelData: slot.modelData
                    others: slot.index === 0 && group.collapsed ? group.items.slice(1) : []
                    onOpenGroup: root.expandedGroup = group.modelData
                }
            }
        }
    }

    // One notification.
    component Card: Item {
        id: card

        required property var modelData
        readonly property Notification n: modelData
        // The rest of its group, counted in the badge while the group is closed.
        // Then a click opens the group, and the ✕ clears all of them.
        property var others: []
        signal openGroup
        readonly property var buttons: Notifications.buttons(card.n)
        // Its picture on the left when that is a mark of the sender's (a
        // logo, an avatar), else the app's icon; content goes under the text.
        readonly property string icon: picture.isIcon ? picture.source : Notifications.iconFor(card.n)

        NotificationPicture {
            id: picture
            notification: card.n
        }

        width: parent.width
        height: content.implicitHeight + root.cardPad * 2
        clip: true

        Behavior on height {
            NumberAnimation {
                duration: Theme.fadeMs
                easing.type: Easing.InOutCubic
            }
        }

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
            height: card.height
            radius: root.cardRadius
            color: fill.focused ? Theme.selectionStrong : Theme.selection
            opacity: fill.focused || hover.hovered ? 1 : 0.5

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.fadeMs
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: card.others.length > 0 ? card.openGroup() : Notifications.activate(card.n)
        }

        Item {
            id: content

            x: root.cardPad
            y: root.cardPad
            width: parent.width - root.cardPad * 2
            implicitHeight: Math.max(iconBox.height, labels.implicitHeight)

            // The app's icon, or a bell on a tile when it sent none. Rounded
            // like the tile, so an avatar is not a hard-cornered square.
            Item {
                id: iconBox

                width: root.iconSize
                height: root.iconSize

                ClippingRectangle {
                    anchors.fill: parent
                    radius: root.iconRadius
                    color: "transparent"
                    visible: appIcon.status === Image.Ready

                    IconImage {
                        id: appIcon

                        anchors.fill: parent
                        source: card.icon
                    }
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
                id: labels

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
                    text: Notifications.styled(card.n?.summary)
                    textFormat: Text.StyledText
                    linkColor: Theme.label2
                    onLinkActivated: link => Notifications.openLink(link)
                    color: card.n?.urgency === NotificationUrgency.Critical ? Theme.warn : Theme.label
                    wrapMode: Text.Wrap
                    maximumLineCount: 10
                    elide: Text.ElideRight
                }

                PopupText {
                    width: parent.width
                    visible: text !== ""
                    text: Notifications.styled(card.n?.body)
                    textFormat: Text.StyledText
                    linkColor: Theme.label2
                    onLinkActivated: link => Notifications.openLink(link)
                    color: Theme.label2
                    wrapMode: Text.Wrap
                    maximumLineCount: 10
                    elide: Text.ElideRight
                    lineHeight: 1.1
                }

                // A content image gets its own space below the text, keeping
                // the header aligned, and is shown whole.
                Item {
                    width: parent.width
                    height: preview.height + 6
                    visible: shot.status === Image.Ready

                    ClippingRectangle {
                        id: preview

                        y: 6
                        width: parent.width
                        height: shot.implicitWidth > 0 ? width * shot.implicitHeight / shot.implicitWidth : 0
                        radius: root.iconRadius
                        color: "transparent"

                        Image {
                            id: shot

                            anchors.fill: parent
                            source: picture.isPreview ? picture.source : ""
                            fillMode: Image.PreserveAspectFit
                            sourceSize.width: Math.ceil(preview.width * 2)
                            asynchronous: true
                        }
                    }
                }

                // The sender's other actions (Notifications.buttons).
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
                            label: modelData.text.trim() || modelData.identifier
                            onTapped: Notifications.run(modelData, card.n)
                        }
                    }
                }
            }
        }
    }
}

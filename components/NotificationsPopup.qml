import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets
import qs
import qs.services

// The bell's popup, which is the notification centre: everything being kept,
// newest first, with clear in its header. It used to be a
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
    dismissWhenEmpty: Notifications.count === 0
    ChoiceBlink { id: choice }

    readonly property int bodyWidth: Theme.popupWideWidth
    // The text's inset from the edge of the popup, as the other popups keep it.
    readonly property int inset: Theme.popupInset
    readonly property int cardPad: 10
    // Cards and the enclosing popup have concentric corners.
    readonly property int cardRadius: Theme.popupRadius - Theme.popupPadding
    readonly property int cardGap: 6
    readonly property int iconSize: 32
    readonly property int iconRadius: 6
    // How tall the list gets before it scrolls: two thirds of the screen,
    // which leaves the popup a popup rather than a panel down the side.
    readonly property int listMax: Math.round((root.screen?.height ?? 1080) * 2 / 3)

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

    // Keep the vacated space through the fade, then move the rows before resizing.
    property var departing: []
    property real departureFade: 0
    property real departureFold: 0
    function clear(items, animate): void {
        if (dismissal.running)
            return;
        if (!root.animateContents || animate === false || Notifications.list.every(n => items.includes(n))) {
            root.dismiss(items);
            return;
        }
        cards.heldHeight = cards.height;
        root.departing = items;
        dismissal.start();
    }

    // Keep the centre available until the last notification is cleared.
    function dismiss(items): void {
        for (const n of items)
            if (Notifications.list.includes(n)) n.dismiss();
        if (Notifications.count === 0)
            OpenPopup.close(root.anchorItem);
    }

    SequentialAnimation {
        id: dismissal
        NumberAnimation { target: root; property: "departureFade"; from: 0; to: 1; duration: Theme.fadeMs }
        NumberAnimation {
            target: root
            property: "departureFold"
            from: 0
            to: 1
            duration: Theme.fadeMs
            easing.type: Easing.OutCubic
        }
        ScriptAction {
            script: {
                root.dismiss(root.departing);
                root.departing = [];
                root.departureFade = 0;
                root.departureFold = 0;
                cards.heldHeight = -1;
            }
        }
        PauseAnimation { duration: Theme.fadeMs }
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
        id: clearAll
        width: root.bodyWidth
        // Over the cards, which run on under it (ScrollUnder).
        z: 1
        title: "Notifications"
        addable: Notifications.count > 0
        addGlyph: Theme.glyph.clearAll
        addLabel: "Clear"
        addName: "Clear all notifications"
        blink: choice
        enabled: !choice.running && !dismissal.running
        onAdd: {
            const items = Notifications.list.slice();
            choice.start(clearAll, () => root.clear(items));
        }
    }

    // Nothing waiting: a line saying so, rather than a header over nothing.
    PopupNote {
        visible: Notifications.count === 0
        width: root.bodyWidth
        bottomPadding: 2
        text: "No notifications"
    }

    // --- the cards --------------------------------------------------------------
    ListView {
        id: cards
        // In the accessibility tree as a list to scroll, half a view a step.
        Accessible.role: Accessible.List
        Accessible.name: "Notifications"
        Accessible.onScrollUpAction: contentY = Math.max(originY, contentY - height / 2)
        Accessible.onScrollDownAction: contentY = Math.min(originY + Math.max(0, contentHeight - height), contentY + height / 2)

        visible: count > 0
        enabled: !dismissal.running
        width: root.bodyWidth
        property real heldHeight: -1
        height: heldHeight >= 0 ? heldHeight : Math.min(contentHeight, root.listMax)
        Behavior on height {
            enabled: root.animateContents && dismissal.running
            NumberAnimation {
                duration: Theme.fadeMs
                easing.type: Easing.OutCubic
            }
        }
        interactive: contentHeight > height
        clip: true

        ScrollUnder {
            parent: cards
            view: cards
            box: root.chromeItem
        }
        spacing: 0
        boundsBehavior: Flickable.StopAtBounds
        SmoothScroll { view: cards }

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
            enabled: root.animateContents && !dismissal.running
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
        required property int index
        readonly property var items: Notifications.list.filter(n => root.groupOf(n) === group.modelData)
        readonly property int remaining: group.items.filter(n => !root.departing.includes(n)).length
        readonly property bool emptying: group.remaining === 0
        readonly property bool open: root.expandedGroup === group.modelData && group.items.length > 1
        readonly property bool collapsed: group.items.length > 1 && !group.open

        // Down to one, it is a card like any other, and it closes so that the
        // next to arrive joins a collapsed group rather than finding it open.
        onItemsChanged: if (group.items.length < 2 && root.expandedGroup === group.modelData)
            root.expandedGroup = ""

        width: ListView.view.width
        height: (implicitHeight + (group.index < root.groups.length - 1 ? root.cardGap : 0))
            * (group.emptying ? 1 - root.departureFold : 1)
        clip: true
        spacing: 0

        // The sender header collapses the group; its clear button dismisses it.
        Item {
            width: parent.width
            height: group.open ? (groupHeader.height + root.cardGap)
                * (!group.emptying && group.remaining < 2 ? 1 - root.departureFold : 1) : 0
            visible: height > 0
            clip: true

            MouseArea {
                anchors.fill: parent
                Accessible.role: Accessible.Button
                Accessible.name: "Collapse " + group.modelData + " notifications"
                Accessible.onPressAction: if (enabled && visible)
                    root.expandedGroup = ""
                readonly property var keyPress: () => root.expandedGroup = ""
                onClicked: root.expandedGroup = ""
            }

            PopupHeader {
                id: groupHeader
                width: parent.width
                title: group.modelData

                PopupButton {
                    id: groupClear
                    framed: true
                    glyph: Theme.glyph.clearAll
                    label: "Clear"
                    blink: choice
                    live: !choice.running
                    onTapped: {
                        const items = group.items.slice();
                        choice.start(groupClear, () => root.clear(items));
                    }
                }
            }
        }

        Repeater {
            model: ScriptModel {
                values: group.items
            }

            // Keep hidden cards ready when their group is opened.
            delegate: Item {
                id: slot
                required property var modelData
                required property int index
                readonly property bool shown: slot.index === 0 || !group.collapsed
                width: parent.width
                height: slot.shown ? (notification.height + notification.y)
                    * (!group.emptying && root.departing.includes(slot.modelData) ? 1 - root.departureFold : 1) : 0
                visible: height > 0
                opacity: slot.shown ? 1 : 0
                clip: true

                Behavior on opacity {
                    enabled: root.animateContents
                    NumberAnimation {
                        duration: Theme.fadeMs
                    }
                }

                Card {
                    id: notification
                    y: slot.index > 0 ? root.cardGap
                        * (group.items.slice(0, slot.index).every(n => root.departing.includes(n)) ? 1 - root.departureFold : 1) : 0
                    modelData: slot.modelData
                    others: slot.index === 0 && group.collapsed ? group.items.slice(1) : []
                    onOpenGroup: root.expandedGroup = group.modelData
                }
            }
        }
    }

    // One notification, or a collapsed group: either swipe clears it.
    component Card: SwipeRow {
        id: card

        required property var modelData
        readonly property Notification n: modelData
        // The rest of its group, counted in the badge while the group is closed.
        // Then a click opens the group, and the ✕ clears all of them.
        property var others: []
        signal openGroup
        function open(): void {
            if (card.others.length > 0) {
                card.openGroup();
                return;
            }
            const n = card.n;
            choice.start(card, () => {
                if (Notifications.list.includes(n)) Notifications.activate(n);
            });
        }
        readonly property var buttons: Notifications.buttons(card.n)
        // Its picture on the left when that is a mark of the sender's (a
        // logo, an avatar), else the app's icon; content goes under the text.
        readonly property string icon: picture.isIcon ? picture.source : Notifications.iconFor(card.n)

        NotificationPicture {
            id: picture
            notification: card.n
        }

        width: parent.width
        fullHeight: content.implicitHeight + root.cardPad * 2
        glyph: Theme.glyph.close
        name: Notifications.plain(card.n?.summary) || card.n?.appName || "Notification"
        blink: choice
        opacity: root.departing.includes(card.n) ? 1 - root.departureFade : 1
        showHighlight: false
        onTapped: card.open()
        onSwiped: root.clear([card.n, ...card.others], false)
        clip: true

        HoverHandler {
            id: hover
        }

        // The card: a faint fill at rest, the row highlight under the
        // pointer, and one step past it on the one the popup was opened on,
        // which is how it says "this one" among the rest.
        Rectangle {
            id: fill

            readonly property bool focused: card.n && card.n === Notifications.centreFocus

            x: card.swipe
            width: parent.width
            height: card.height
            radius: root.cardRadius
            color: fill.focused ? Theme.selectionStrong : Theme.selection
            opacity: choice.item === card ? (choice.lit ? 1 : 0) : fill.focused || hover.hovered || card.swiping ? 1 : 0.5

            Behavior on opacity {
                enabled: root.animateContents && choice.item !== card
                NumberAnimation {
                    duration: Theme.fadeMs
                }
            }
        }

        Item {
            id: content

            x: root.cardPad + card.swipe
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
                        name: "Dismiss notification"

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: hover.hovered
                        glyph: Theme.glyph.close
                        glyphSize: Theme.captionSize
                        live: !choice.running
                        onTapped: {
                            const items = [card.n, ...card.others];
                            choice.start(card, () => root.clear(items));
                        }
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
                            sourceSize.width: Math.ceil(preview.width * (QsWindow.window?.devicePixelRatio ?? 1))
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
                            live: !choice.running
                            onTapped: {
                                const action = modelData;
                                const n = card.n;
                                choice.start(card, () => {
                                    if (Notifications.list.includes(n)) Notifications.run(action, n);
                                });
                            }
                        }
                    }
                }
            }
        }
    }
}

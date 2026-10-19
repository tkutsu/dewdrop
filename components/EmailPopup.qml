import QtQuick
import qs
import qs.components
import qs.services

// Unread mail, newest first, as a list to clear rather than
// one to read: a swipe archives or marks read, and every verb can be taken
// back from the header for a few seconds (Email.act). A click on a row opens
// it in place to be read, with its three verbs (archive, mark read, star) over
// the time column and its foot holding the rest (open in Gmail,
// unsubscribe, the login code, the attachments). Acting
// on the open mail opens the next one. Unread in the inbox tabs that do not
// count (Settings.mailCategories) is one folded row at the end. The plus at the header's right end writes a new one.
//
// Two lines a row beside the sender's monogram, the way Gmail's list reads:
// the sender and the time, then the subject with as much of the opening as
// fits after it. Nothing wraps; a mail is opened to be read, and the row only
// has to say which one it is.
Popup {
    id: root

    readonly property int bodyWidth: Theme.popupWideWidth
    // The air between threads, closer than between the popup's parts.
    readonly property int rowGap: 3
    readonly property int rowPad: 4
    // The text's inset from the edge of the row's highlight.
    readonly property int inset: Theme.popupInset
    // The sender's disc, and where the row's text starts after it.
    readonly property int monogram: 26
    readonly property int textX: root.inset + root.monogram + 8
    // A fixed column, so the times line up down the right edge.
    readonly property int whenWidth: 44
    readonly property int batch: 8
    property int cap: batch
    readonly property int listMax: Math.max(120, Math.min(560, (root.screen?.height ?? 900) - 160))
    readonly property bool loadingMore: Email.loading && root.rows.length < Math.min(root.cap, Email.total)

    readonly property var rows: Email.threads.slice(0, root.cap)
    // The rest of the inbox, unfolded in place under its row.
    property bool otherOpen: false
    readonly property var otherRows: root.otherOpen ? Email.otherThreads : []
    // Every mail on show, in order: where the next one to open is found.
    readonly property var shown: root.rows.concat(root.otherRows)

    // The thread opened in place, by id. One at a time: two open mails would
    // be a page, not a popup.
    property string expanded: ""
    // How tall an open mail may get before it scrolls.
    readonly property int bodyMax: 240
    // The gutter an open thread's rail runs down, when it has several mails.
    readonly property int railWidth: 12
    // The open mail's foot under its text: its buttons and the gap above.
    readonly property int footHeight: 26
    // The latest action still waiting, taken back by the header's undo.
    readonly property var lastAction: Email.pending[Email.pending.length - 1] ?? null

    // Measure the closed rows directly: subtracting animated heights from
    // the Column's delayed layout makes the reserved window size fluctuate.
    readonly property real collapsedListHeight: {
        let h = 0, n = 0;
        for (const child of rowList.children) {
            // The Repeaters stand in the Column too, with no height.
            if (!child.visible || child.height === 0)
                continue;
            h += child.collapsedHeight ?? child.height;
            n++;
        }
        return h + Math.max(0, n - 1) * root.rowGap;
    }

    // The window is held at the height of a fully open mail, so a row opening
    // grows the box inside it rather than resizing the popup every frame of
    // the animation (see Popup.reserveHeight). The body adds 12 pixels of
    // padding and one extra pixel of spacing below the subject.
    reserveHeight: {
        let h = root.vPadding + root.bottomPadding + Math.min(root.collapsedListHeight + root.bodyMax + 13 + root.footHeight, root.listMax);
        for (const item of root.content) {
            if (item !== threadList && item.visible)
                h += item.height + root.spacing;
        }
        return h;
    }

    // The text of every row on show, asked for as the popup opens, so a row
    // opens straight to its full height instead of to the snippet and then
    // again when the text lands. Each is read once a session.
    onShownChanged: root.preload()
    Component.onCompleted: root.preload()

    function preload(): void {
        for (const r of root.shown)
            Email.read(r);
    }

    function loadMore(): void {
        if (Email.threads.length >= root.cap)
            root.cap = Math.min(root.cap + root.batch, Email.total);
        Email.loadMore(root.cap);
    }

    // A verb on a row. Acting on the open mail opens the one below it, or
    // the one above when it was the last, so a run of mail is read and
    // cleared without reaching for the next row. A list left empty closes.
    function act(kind: string, thread: var, options: var): void {
        const wasOpen = root.expanded === thread.id;
        const leaves = kind !== "star" && kind !== "unstar";
        let next = null;
        if (wasOpen && leaves) {
            const i = root.shown.findIndex(t => t.id === thread.id);
            next = root.shown[i + 1] ?? root.shown[i - 1] ?? null;
        }
        Email.act(kind, thread, Object.assign({ wasOpen: wasOpen }, options ?? {}));
        if (wasOpen && leaves) {
            root.expanded = next?.id ?? "";
            if (next)
                Email.read(next);
        }
        if (leaves && Email.total === 0 && (Email.other === 0 || !root.otherOpen))
            OpenPopup.close(root.anchorItem);
    }

    // Kept for the launcher's habit and the tests: reading is a verb.
    function markRead(thread): void {
        root.act("read", thread);
    }

    // Whatever is still waiting goes as the popup does: there is no undo
    // left to offer once it is shut.
    function settle(): void {
        Email.flush();
        root.otherOpen = false;
    }

    onVisibleChanged: if (!root.visible)
        root.settle()
    Component.onDestruction: root.settle()
    onOtherOpenChanged: Email.otherWanted = root.otherOpen

    // New mail lands in the list in front of you rather than on a card.
    Binding {
        target: Email
        property: "popupOpen"
        value: root.visible
    }

    // An undone mail comes back as it left: open, if it was.
    Connections {
        target: Email

        function onRestored(row, wasOpen) {
            if (Email.otherThreads.some(t => t.id === row.id))
                root.otherOpen = true;
            if (wasOpen) {
                root.expanded = row.id;
                Email.read(row);
            }
        }
    }

    // A new mail at the right end, where every popup under the bar keeps its
    // plus. Gmail itself is the row at the foot, and a right click on the bar
    // icon.
    PopupHeader {
        width: root.bodyWidth
        // Over the threads, which run on under it (ScrollUnder).
        z: 1
        title: "Mail"
        addable: true
        onAdd: {
            OpenPopup.dismiss();
            Email.compose("");
        }

        ReconnectButton {}

        RetryButton { service: Email }

        // Takes back the latest action still waiting.
        PopupButton {
            id: undoButton
            visible: root.lastAction !== null
            framed: true
            glyph: Theme.glyph.undo
            label: "Undo"
            name: root.lastAction ? `Undo: ${root.lastAction.said}` : "Undo"
            onTapped: Email.undo()
        }

        PopupButton {
            framed: true
            glyph: Theme.glyph.openApp
            name: "Open Gmail"
            onTapped: {
                OpenPopup.dismiss();
                Email.openInbox();
            }
        }
    }

    // What went wrong since the list loaded. Before that, the line below
    // says it in place of the list.
    PopupNote {
        width: root.bodyWidth
        visible: Email.loaded && Email.trouble !== "" && Email.trouble !== Google.reconnect
        text: Email.trouble
        warn: true
        font.pixelSize: Theme.footnoteSize
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
    }

    PopupNote {
        width: root.bodyWidth
        visible: !Email.loaded || root.rows.length === 0
        text: !Email.loaded ? Email.tooltip : Email.total === 0 ? "No unread mail"
            : Email.trouble || (Email.loading ? "Reading mail…" : "Unread mail details unavailable")
    }

    Flickable {
        id: threadList

        // In the accessibility tree as a list to scroll, half a view a step.

        Accessible.role: Accessible.List

        Accessible.name: "Mail"

        Accessible.onScrollUpAction: contentY = Math.max(originY, contentY - height / 2)

        Accessible.onScrollDownAction: contentY = Math.min(originY + Math.max(0, contentHeight - height), contentY + height / 2)

        width: root.bodyWidth
        height: Math.min(rowList.implicitHeight, root.listMax)
        visible: rowList.implicitHeight > 0
        contentHeight: rowList.implicitHeight
        clip: true

        ScrollUnder {
            parent: threadList
            view: threadList
            box: root.chromeItem
        }
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        SmoothScroll { view: threadList }
        acceptedButtons: Qt.NoButton

        Column {
            id: rowList
            width: parent.width
            spacing: root.rowGap

            Repeater {
                id: list

                model: root.rows
                delegate: mailRow
            }

            PopupRow {
                id: more
                name: "Load more mail"
                width: root.bodyWidth
                height: moreLabel.implicitHeight + root.rowPad * 2
                visible: Email.loaded && Email.total > root.rows.length && root.rows.length > 0
                enabled: !root.loadingMore
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: root.loadMore()

                HoverHandler {
                    cursorShape: more.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                }

                PopupText {
                    id: moreLabel
                    x: root.textX
                    y: root.rowPad
                    width: parent.width - root.textX - root.inset
                    text: root.loadingMore ? "Loading" : `Load more (${Email.total - root.rows.length})`
                    font.pixelSize: Theme.footnoteSize
                    color: Theme.label2
                }
            }

            // The other tabs' unread, one row until it is asked for. It
            // unfolds into the same rows with the same verbs.
            PopupRow {
                id: otherRow
                name: root.otherOpen ? "Fold other mail" : "Other mail"
                width: root.bodyWidth
                height: otherLabel.implicitHeight + root.rowPad * 2
                visible: Email.loaded && Email.other > 0
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: root.otherOpen = !root.otherOpen

                Glyph {
                    x: root.inset + Math.round((root.monogram - width) / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.otherOpen ? Theme.glyph.sectionOpen : Theme.glyph.sectionShut
                    fontSize: Theme.footnoteSize
                    color: Theme.label2
                }

                PopupText {
                    id: otherLabel
                    x: root.textX
                    y: root.rowPad
                    width: parent.width - root.textX - root.inset
                    text: `Other · ${Email.other}`
                    font.pixelSize: Theme.footnoteSize
                    color: Theme.label2
                }
            }

            Repeater {
                id: otherList

                model: root.otherRows
                delegate: mailRow
            }
        }
    }

    Component {
        id: mailRow

        SwipeRow {
            id: row

            required property var modelData

            name: row.modelData.subject || "Mail thread"
            width: root.bodyWidth
            readonly property bool isOpen: root.expanded === row.modelData.id
            readonly property real collapsedHeight: from.implicitHeight + subject.implicitHeight + lines.spacing + root.rowPad * 2
            // The verbs are out on the open mail only; a row under the
            // pointer keeps its time, and a swipe or a click does the rest.
            readonly property bool showVerbs: !row.swiping && row.isOpen

            // Left archives, right marks read, on the touchpad or with a
            // mouse drag on a closed row or an open mail's empty space.
            // Touchpad swipes stay on the row's two lines; open rows route
            // their mouse presses below.
            leftGlyph: Theme.glyph.mailArchive
            rightGlyph: Theme.glyph.mailRead
            fullHeight: lines.implicitHeight + root.rowPad * 2
            gestureHeight: row.collapsedHeight
            draggable: !row.isOpen
            onSwiped: left => root.act(left ? "archive" : "read", row.modelData)

            gesturePolicy: TapHandler.ReleaseWithinBounds
            acceptsTap: !row.isOpen
            onTapped: {
                if (row.swiping)
                    return;
                if (row.isOpen) {
                    root.expanded = "";
                } else {
                    root.expanded = row.modelData.id;
                    Email.read(row.modelData);
                }
            }

            // Leave text and controls their press; only the air around them
            // closes or swipes the open mail. Decide at press time so a drag
            // can cross text without turning into a selection midway through.
            function interactiveAt(item: Item, point: point): bool {
                if (!item.visible || item.opacity === 0)
                    return false;
                const local = item.mapFromItem(row, point.x, point.y);
                const inside = item.contains(local);
                if (!inside && item.clip)
                    return false;
                if (item instanceof PopupButton)
                    return inside;
                if (item instanceof TextEdit)
                    return inside && item.hasTextAt(local);
                for (const child of item.children) {
                    if (row.interactiveAt(child, point))
                        return true;
                }
                return false;
            }

            MouseArea {
                anchors.fill: parent
                z: 2
                enabled: row.isOpen && !row.leaving
                acceptedButtons: Qt.LeftButton
                preventStealing: true
                property real startX: 0
                property real startY: 0
                property bool moved: false
                onPressed: mouse => {
                    if (row.interactiveAt(lines, Qt.point(mouse.x, mouse.y))) {
                        mouse.accepted = false;
                        return;
                    }
                    startX = mouse.x;
                    startY = mouse.y;
                    moved = false;
                }
                onPositionChanged: mouse => {
                    if (pressed && Math.abs(mouse.y - startY) >= Qt.styleHints.startDragDistance)
                        moved = true;
                    if (pressed && (row.tracking || Math.abs(mouse.x - startX) >= Qt.styleHints.startDragDistance))
                        row.track(mouse.x - startX);
                }
                onReleased: mouse => {
                    if (row.tracking)
                        row.release();
                    else if (!moved && contains(Qt.point(mouse.x, mouse.y)))
                        root.expanded = "";
                }
                onCanceled: {
                    row.tracking = false;
                    row.swipe = 0;
                }
            }

            // The sender's initials on a disc, centred on the closed row's
            // two lines and staying there as the mail opens under them.
            Rectangle {
                x: root.inset + row.swipe
                y: Math.round((row.collapsedHeight - height) / 2)
                width: root.monogram
                height: width
                radius: width / 2
                color: Theme.monogramTones[Email.toneOf(row.modelData.address || row.modelData.from, Theme.monogramTones.length)]

                PopupText {
                    anchors.centerIn: parent
                    text: Email.initials(row.modelData.from)
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.footnoteSize
                    font.weight: Font.DemiBold
                    color: Theme.badgeFg
                }
            }

            Column {
                id: lines

                x: root.textX + row.swipe
                y: root.rowPad
                width: row.width - root.textX - root.inset
                spacing: 1

                Item {
                    width: parent.width
                    height: from.implicitHeight

                    PopupText {
                        id: from
                        width: Math.min(implicitWidth, parent.width - (row.showVerbs ? verbs.width + 4 : root.whenWidth + (starMark.visible ? starMark.width + 3 : 0)) - count.width)
                        text: row.modelData.from
                        textFormat: Text.PlainText
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

                    // A starred mail says so beside its time while the
                    // verbs are away.
                    Glyph {
                        id: starMark
                        anchors.right: parent.right
                        anchors.rightMargin: root.whenWidth + 3
                        anchors.verticalCenter: from.verticalCenter
                        visible: row.modelData.starred && !row.showVerbs
                        text: Theme.glyph.mailStar
                        fontSize: Theme.footnoteSize
                        color: Theme.label2
                    }

                    PopupText {
                        anchors.right: parent.right
                        anchors.baseline: from.baseline
                        text: Email.sayWhen(row.modelData.at)
                        font.pixelSize: Theme.footnoteSize
                        color: Theme.label2
                        opacity: row.showVerbs ? 0 : 1
                    }

                    // The three verbs, always in the same place and order,
                    // over the time column. Centred on the line and a little
                    // taller than it, into the row's padding, so they come
                    // and go without moving anything. Faded rather than
                    // hidden, so they stay in the accessibility tree.
                    Row {
                        id: verbs

                        anchors.right: parent.right
                        anchors.rightMargin: -4
                        anchors.verticalCenter: from.verticalCenter
                        opacity: row.showVerbs ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.fadeMs
                                easing.type: Easing.InOutCubic
                            }
                        }

                        PopupButton {
                            id: archiveButton
                            glyph: Theme.glyph.mailArchive
                            name: "Archive"
                            onTapped: root.act("archive", row.modelData)
                        }

                        PopupButton {
                            id: readButton
                            glyph: Theme.glyph.mailRead
                            name: "Mark read"
                            onTapped: root.act("read", row.modelData)
                        }

                        PopupButton {
                            id: starButton
                            glyph: row.modelData.starred ? Theme.glyph.mailStar : Theme.glyph.mailStarred
                            name: row.modelData.starred ? "Unstar" : "Star"
                            onTapped: root.act(row.modelData.starred ? "unstar" : "star", row.modelData)
                        }
                    }
                }

                // The subject takes what it needs and the snippet what is left,
                // so a short subject shows more of the mail and a long one
                // pushes the snippet off the end rather than being cut itself.
                Item {
                    width: parent.width
                    height: subject.implicitHeight

                    PopupText {
                        id: subject
                        width: Math.min(implicitWidth, parent.width)
                        text: row.modelData.subject
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.captionSize
                        color: Theme.label
                        elide: Text.ElideRight
                    }

                    PopupText {
                        x: subject.width
                        width: parent.width - subject.width
                        visible: !row.isOpen && width > 30 && text !== ""
                        leftPadding: 6
                        text: row.modelData.snippet
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.captionSize
                        color: Theme.label2
                        elide: Text.ElideRight
                    }
                }

                // The mail itself, once the row is open, unrolling downwards
                // from under the subject, with its foot under it. The snippet
                // stands in, faintly, if the text has not landed yet, and the
                // height follows it when it does rather than jumping. Scrolls
                // past bodyMax rather than growing the popup down the screen.
                //
                // One mail is its text alone. Several unread in the thread are
                // each under who sent it and when, oldest first, strung on a
                // rail down the left: a dot at each sender, and a line from one
                // to the next.
                Item {
                    id: reveal

                    visible: height > 0
                    width: parent.width
                    height: row.isOpen ? (details.item?.height ?? 0) + 12 + root.footHeight : 0
                    clip: true

                    Behavior on height {
                        enabled: root.animateContents
                        NumberAnimation {
                            duration: Theme.foldMs
                            easing.type: Easing.InOutCubic
                        }
                    }

                    Loader {
                        id: details
                        y: 6
                        width: parent.width
                        active: row.isOpen || reveal.height > 0
                        sourceComponent: Component {
                            Flickable {
                                id: mail

                                // In the accessibility tree as a list to scroll, half a view a step.

                                Accessible.role: Accessible.List

                                Accessible.name: "Message"

                                Accessible.onScrollUpAction: contentY = Math.max(originY, contentY - height / 2)

                                Accessible.onScrollDownAction: contentY = Math.min(originY + Math.max(0, contentHeight - height), contentY + height / 2)

                                width: details.width
                                height: Math.min(chain.implicitHeight, root.bodyMax)
                                contentHeight: chain.implicitHeight
                                clip: true
                                layer.enabled: contentHeight > height
                                layer.effect: ScrollEdges {
                                    view: mail
                                }
                                boundsBehavior: Flickable.StopAtBounds
                                SmoothScroll { view: mail }
                                acceptedButtons: Qt.NoButton

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
                                                        textFormat: Text.PlainText
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

                                                TextEdit {
                                                    id: messageText
                                                    width: parent.width
                                                    text: Email.richText(link.fetched !== undefined ? link.fetched : link.modelData.snippet + "…")
                                                    font.family: Theme.bodyFont
                                                    font.pixelSize: Theme.captionSize
                                                    color: link.fetched !== undefined ? Theme.label : Theme.label3
                                                    selectionColor: Theme.textSelection
                                                    selectedTextColor: Theme.label
                                                    readOnly: true
                                                    selectByMouse: true
                                                    persistentSelection: true
                                                    activeFocusOnPress: false
                                                    wrapMode: TextEdit.Wrap
                                                    textFormat: TextEdit.RichText

                                                    // positionAt clamps to the nearest cursor even in
                                                    // empty space. Check the adjacent character boxes.
                                                    function hasTextAt(point: point): bool {
                                                        if (linkAt(point.x, point.y) !== "")
                                                            return true;
                                                        const at = positionAt(point.x, point.y);
                                                        for (let i = Math.max(0, at - 1); i <= Math.min(length - 1, at); i++) {
                                                            const character = getText(i, i + 1);
                                                            if (character === "\n" || character === "\u2028" || character === "\u2029")
                                                                continue;
                                                            const a = positionToRectangle(i);
                                                            const b = positionToRectangle(i + 1);
                                                            const end = a.y === b.y ? b.x : a.x + messageMetrics.advanceWidth(character);
                                                            if (point.y >= a.y && point.y < a.y + a.height
                                                                && point.x >= Math.min(a.x, end) && point.x <= Math.max(a.x, end))
                                                                return true;
                                                        }
                                                        return false;
                                                    }

                                                    FontMetrics {
                                                        id: messageMetrics
                                                        font: messageText.font
                                                    }
                                                    onLinkActivated: url => {
                                                        if (/^https?:\/\//i.test(url)) {
                                                            OpenPopup.dismiss();
                                                            Qt.openUrlExternally(url);
                                                        }
                                                    }

                                                    // Right-click copies the selection, or the whole message.
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        acceptedButtons: Qt.RightButton
                                                        Accessible.role: Accessible.StaticText
                                                        Accessible.name: "Message text"
                                                        Accessible.description: "Pointer: right click"
                                                        cursorShape: messageText.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
                                                        onClicked: {
                                                            if (messageText.selectedText === "")
                                                                messageText.selectAll();
                                                            messageText.copy();
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

                    // The open mail's foot: what to do with it besides the
                    // three verbs above, and what to take out of it.
                    Row {
                        id: foot

                        y: 6 + (details.item?.height ?? 0) + 6
                        spacing: 4

                        PopupButton {
                            framed: true
                            glyph: Theme.glyph.openApp
                            label: "Open"
                            name: "Open in Gmail"
                            onTapped: {
                                OpenPopup.dismiss();
                                Email.open(row.modelData);
                            }
                        }

                        // Only when the mail offers a way off its list on the
                        // web. One click and archived when the sender takes a
                        // one-click unsubscribe; its page otherwise.
                        PopupButton {
                            readonly property var unsubscribe: row.modelData.unsubscribe ?? null

                            visible: unsubscribe !== null
                            framed: true
                            glyph: Theme.glyph.mailUnsubscribe
                            label: "Unsub"
                            name: "Unsubscribe"
                            onTapped: {
                                if (unsubscribe.oneClick) {
                                    root.act("archive", row.modelData, {
                                        said: "Unsubscribed",
                                        also: Email.unsubscribe
                                    });
                                } else {
                                    OpenPopup.dismiss();
                                    Qt.openUrlExternally(unsubscribe.url);
                                }
                            }
                        }

                        // A login code, to copy without reading for it.
                        // Copying it is reading it: the mail is marked read
                        // with it, and the undo takes back the read (the
                        // clipboard keeps it).
                        PopupButton {
                            readonly property string code: Email.codeIn(row.modelData)

                            visible: code !== ""
                            framed: true
                            glyph: Theme.glyph.copy
                            label: code
                            name: "Copy code " + code
                            onTapped: {
                                Email.copy(code);
                                root.act("read", row.modelData, { said: "Code copied" });
                            }
                        }

                        // Everything the thread came with, into Downloads.
                        // Faint while any of it is still on its way.
                        PopupButton {
                            readonly property var parts: Email.partsIn(row.modelData)

                            visible: parts.length > 0
                            live: !parts.some(p => Email.saving[p.part.id])
                            framed: true
                            glyph: Theme.glyph.download
                            label: "Download"
                            name: parts.length === 1 ? "Download " + parts[0].part.name : `Download ${parts.length} attachments`
                            onTapped: Email.saveAll(parts)
                        }
                    }
                }
            }
        }
    }
}

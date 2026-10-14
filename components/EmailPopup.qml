import QtQuick
import qs
import qs.components
import qs.services

// Unread mail in the Primary tab, newest first, as a list to clear rather than
// one to read: every row carries its three verbs (archive, mark read, star),
// which take over the time column under the pointer, and every verb can be
// taken back from the foot for a few seconds (Email.act). A click on a row
// opens it in place to be read; its foot holds the rest (open in Gmail). Acting
// on the open mail opens the next one. The rest of the inbox's unread is one
// folded row at the end. The plus at the header's right end writes a new one.
//
// Two lines a row beside the sender's monogram, the way Gmail's list reads:
// the sender and the time, then the subject with as much of the opening as
// fits after it. Nothing wraps; a mail is opened to be read, and the row only
// has to say which one it is.
Popup {
    id: root

    readonly property int bodyWidth: 340
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
    // The undo line at the popup's foot, held in the window's height whether
    // it shows or not, so it comes and goes without a resize.
    readonly property int undoHeight: 30
    readonly property var lastAction: Email.pending[Email.pending.length - 1] ?? null
    // Its words, kept while the line folds away rather than going blank
    // under it.
    property string lastSaid: ""
    onLastActionChanged: if (root.lastAction)
        root.lastSaid = root.lastAction.said

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
        return h + Math.max(0, n - 1) * root.spacing;
    }

    // The window is held at the height of a fully open mail, so a row opening
    // grows the box inside it rather than resizing the popup every frame of
    // the animation (see Popup.reserveHeight). The body adds 12 pixels of
    // padding and one extra pixel of spacing below the subject.
    reserveHeight: {
        let h = root.vPadding + root.bottomPadding + Math.min(root.collapsedListHeight + root.bodyMax + 13 + root.footHeight, root.listMax);
        for (const item of root.content) {
            if (item !== threadList && item !== undoSlot && item.visible)
                h += item.height + root.spacing;
        }
        return h + root.undoHeight;
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

    spacing: 3

    // A new mail at the right end, where every popup under the bar keeps its
    // plus. Gmail itself is a right click on the bar icon.
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
    }

    // What went wrong since the list loaded. Before that, the line below
    // says it in place of the list.
    PopupText {
        width: root.bodyWidth
        leftPadding: root.inset
        rightPadding: root.inset
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
        rightPadding: root.inset
        visible: !Email.loaded || root.rows.length === 0
        text: !Email.loaded ? Email.tooltip : Email.total === 0 ? "No unread mail"
            : Email.trouble || (Email.loading ? "Reading mail..." : "Unread mail details unavailable")
        color: Theme.label2
        wrapMode: Text.WordWrap
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
            spacing: root.spacing

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
                    text: root.loadingMore ? "Loading..." : `Load more (${Email.total - root.rows.length})`
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

    // The latest action still waiting, and the way to take it back. It
    // folds in under the list, in room the window keeps for it anyway.
    Item {
        id: undoSlot

        width: root.bodyWidth
        height: root.lastAction ? root.undoHeight : 0
        visible: height > 0
        clip: true

        Behavior on height {
            NumberAnimation {
                duration: Theme.foldMs
                easing.type: Easing.InOutCubic
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.undoHeight - height - 4
            spacing: 8

            PopupText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.lastSaid
                font.pixelSize: Theme.footnoteSize
                color: Theme.label2
            }

            PopupButton {
                anchors.verticalCenter: parent.verticalCenter
                framed: true
                glyph: Theme.glyph.undo
                label: "undo"
                name: "Undo"
                live: root.lastAction !== null
                onTapped: Email.undo()
            }
        }
    }

    Component {
        id: mailRow

        PopupRow {
            id: row

            required property var modelData

            name: row.modelData.subject || "Mail thread"
            width: root.bodyWidth
            readonly property bool isOpen: root.expanded === row.modelData.id
            readonly property real collapsedHeight: from.implicitHeight + subject.implicitHeight + lines.spacing + root.rowPad * 2
            // The verbs are out under the pointer, when the keys reach the
            // row or one of them, and all the time on the open mail.
            readonly property bool showVerbs: !row.swiping && (row.hovered || row.isOpen || archiveButton.keyed || readButton.keyed || starButton.keyed)

            // --- swipe -------------------------------------------------------
            // Left archives, right marks read, on the touchpad or with a
            // mouse drag on the row's two lines. The row moves the way content
            // scrolls on this machine, the colour of what letting go will do
            // opens behind it, and past `reach` its glyph pops: letting go
            // there slides the row off and folds it away. Short of it, the row
            // springs back.
            property real swipe: 0
            readonly property real reach: row.width * 0.4
            readonly property bool armed: Math.abs(row.swipe) >= row.reach
            readonly property bool swiping: row.swipe !== 0 || row.tracking
            property bool tracking: false
            property bool leaving: false
            // How far the row has folded away once it has slid off.
            property real gone: 0
            // The gesture's axis, fixed by its first movement, so a scroll
            // that drifts sideways never becomes a swipe.
            property string axis: ""

            Behavior on swipe {
                enabled: !row.tracking && !row.leaving
                SpringAnimation {
                    spring: Theme.drawerSpring
                    damping: Theme.drawerDamping
                }
            }

            function track(dx: real): void {
                row.tracking = true;
                row.swipe = Math.max(-row.width, Math.min(row.width, dx));
            }

            function release(): void {
                if (!row.tracking)
                    return;
                row.tracking = false;
                if (row.armed && !row.leaving) {
                    row.leaving = true;
                    slideOff.to = row.swipe < 0 ? -row.width : row.width;
                    leave.kind = row.swipe < 0 ? "archive" : "read";
                    leave.start();
                } else {
                    row.swipe = 0;
                }
            }

            SequentialAnimation {
                id: leave

                property string kind: ""

                NumberAnimation {
                    id: slideOff
                    target: row
                    property: "swipe"
                    duration: 140
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: row
                    property: "gone"
                    to: 1
                    duration: Theme.foldMs * 0.6
                    easing.type: Easing.InOutCubic
                }
                ScriptAction {
                    script: root.act(leave.kind, row.modelData)
                }
            }

            // The gesture ends when the touchpad says so, or failing that
            // when it has gone quiet.
            Timer {
                id: quiet
                interval: 150
                onTriggered: {
                    row.axis = "";
                    row.release();
                }
            }

            height: (lines.implicitHeight + root.rowPad * 2) * (1 - row.gone)
            clip: row.leaving

            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: {
                if (reveal.bodyHovered || row.swiping)
                    return;
                if (row.isOpen) {
                    root.expanded = "";
                } else {
                    root.expanded = row.modelData.id;
                    Email.read(row.modelData);
                }
            }

            // What letting go will do, opening from the edge the row is
            // leaving: archive at the right, mark read at the left.
            Rectangle {
                visible: row.swipe !== 0
                x: row.swipe < 0 ? row.width + row.swipe : 0
                width: Math.abs(row.swipe)
                height: row.height
                radius: Theme.selectionRadius
                color: row.swipe < 0 ? Theme.swipeArchive : Theme.swipeRead
                opacity: row.armed ? 1 : 0.6
                clip: true

                Glyph {
                    // Centred in the room it would have once armed, so it
                    // rides in with the edge and then holds still.
                    x: (row.swipe < 0 ? parent.width - Math.min(parent.width, row.reach) / 2 : Math.min(parent.width, row.reach) / 2) - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.swipe < 0 ? Theme.glyph.mailArchive : Theme.glyph.mailRead
                    fontSize: Theme.popupTextSize
                    color: Theme.badgeFg
                    scale: row.armed ? 1.3 : 1

                    Behavior on scale {
                        SpringAnimation {
                            spring: 4
                            damping: 0.3
                        }
                    }
                }
            }

            // Where a swipe is taken: the row's two lines and not the open
            // mail under them, whose text is dragged to select. On top, so it
            // sees the wheel first and hands back whatever is not sideways,
            // and its drag only takes over from a press once it has moved.
            Item {
                z: 1
                width: row.width
                height: row.collapsedHeight

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: wheel => {
                        const dx = wheel.pixelDelta.x;
                        const dy = wheel.pixelDelta.y;
                        // Momentum after a swipe is the swipe's; after a
                        // scroll it is the scroll's.
                        if (wheel.phase === Qt.ScrollMomentum) {
                            wheel.accepted = row.axis === "x" || row.leaving;
                            return;
                        }
                        if (wheel.phase === Qt.ScrollBegin)
                            row.axis = "";
                        if (row.axis === "" && (dx !== 0 || dy !== 0))
                            row.axis = Math.abs(dx) > Math.abs(dy) ? "x" : "y";
                        if (row.axis !== "x" || row.leaving) {
                            wheel.accepted = row.leaving;
                            if (wheel.phase === Qt.ScrollEnd)
                                row.axis = "";
                            else if (row.axis !== "")
                                quiet.restart();
                            return;
                        }
                        wheel.accepted = true;
                        row.track(row.swipe + dx);
                        if (wheel.phase === Qt.ScrollEnd) {
                            quiet.stop();
                            row.axis = "";
                            row.release();
                        } else {
                            quiet.restart();
                        }
                    }
                }

                DragHandler {
                    target: null
                    yAxis.enabled: false
                    enabled: !row.leaving
                    onActiveChanged: if (!active)
                        row.release()
                    onActiveTranslationChanged: if (active)
                        row.track(activeTranslation.x)
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
                Row {
                    width: parent.width

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
                    readonly property bool bodyHovered: bodyHover.hovered

                    HoverHandler { id: bodyHover }

                    visible: height > 0
                    width: parent.width
                    height: row.isOpen ? (details.item?.height ?? 0) + 12 + root.footHeight : 0
                    clip: true

                    Behavior on height {
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
                    // three verbs above.
                    Row {
                        id: foot

                        y: 6 + (details.item?.height ?? 0) + 6
                        spacing: 4

                        PopupButton {
                            framed: true
                            glyph: Theme.glyph.openApp
                            label: "open"
                            name: "Open in Gmail"
                            onTapped: {
                                OpenPopup.dismiss();
                                Email.open(row.modelData);
                            }
                        }
                    }
                }
            }
        }
    }
}

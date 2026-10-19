import QtQuick
import Quickshell
import Quickshell.Widgets
import qs
import qs.components
import qs.services

// What has not been seen yet, as a list to clear the way mail is: the
// week's videos from the channels followed, then each feed's stories, each
// part folded under a header with its count until a click opens it. A click
// on a row opens it in the browser, a swipe either way puts it away, and
// both count it seen, so it leaves the list and the badge. The header takes
// back the swipes (and "Mark All Seen") until the popup closes.
Popup {
    id: root

    readonly property int bodyWidth: Theme.popupWideWidth
    readonly property int rowGap: 3
    readonly property int rowPad: 4
    readonly property int inset: Theme.popupInset
    // 16:9, two text lines tall.
    readonly property int thumbWidth: 64
    readonly property int thumbHeight: 36
    readonly property int textX: root.inset + root.thumbWidth + 8
    readonly property int listMax: Math.max(120, Math.min(560, (root.screen?.height ?? 900) - 160))
    // Animate the box inside a fixed surface, avoiding compositor repositioning.
    reserveHeight: root.vPadding + root.bottomPadding + feedHeader.height + root.spacing + root.listMax
        + (troubleNote.visible ? troubleNote.height + root.spacing : 0)
        + (emptyNote.visible ? emptyNote.height + root.spacing : 0)
    readonly property int sectionFadeMs: Math.round(Theme.fadeMs * 2 / 3)
    readonly property int sectionFoldMs: Math.round(Theme.foldMs * 2 / 3)
    // Ages move on the minute.
    readonly property real now: Google.now.getTime()
    readonly property string requestedSection: root.sections.find(s => Feeds.unfolded(s.section))?.section ?? ""
    property string shownSection: ""
    property real sectionOpacity: 1
    property real sectionExpansion: 1
    property bool sectionReady: false
    property var sectionKeys: []
    property string movingSection: ""
    property real headerOffset: 0
    property real headerExpansion: 1
    property real heldListHeight: -1

    onRequestedSectionChanged: root.updateSection()
    onSectionsChanged: root.syncSectionOrder()
    Component.onCompleted: {
        root.syncSectionOrder();
        root.sectionReady = true;
        root.updateSection();
    }

    // Retain positions on close and refresh; newly available feeds join the end.
    function syncSectionOrder(): void {
        const keys = root.sections.map(s => s.section);
        root.sectionKeys = root.sectionKeys.filter(key => keys.includes(key))
            .concat(keys.filter(key => !root.sectionKeys.includes(key)));
    }

    function moveSectionLast(section: string): void {
        if (section !== "" && root.sectionKeys.includes(section))
            root.sectionKeys = root.sectionKeys.filter(key => key !== section).concat([section]);
    }

    // Move the selected header last, then fade its content in after it arrives.
    function updateSection(): void {
        if (!root.sectionReady)
            return;
        // Hold the viewport through interruptions too, then ease the viewport to its final size.
        root.heldListHeight = view.height;
        viewportResize.stop();
        sectionTransition.stop();
        root.headerOffset = 0;
        root.headerExpansion = 1;
        root.movingSection = "";
        if (Settings.reduceMotion || !root.visible) {
            root.moveSectionLast(root.requestedSection);
            root.shownSection = root.requestedSection;
            root.sectionOpacity = 1;
            root.sectionExpansion = 1;
            root.heldListHeight = -1;
        } else if (root.shownSection !== root.requestedSection || root.sectionOpacity < 1 || root.sectionExpansion < 1) {
            if (root.requestedSection !== "" && root.sectionKeys.indexOf(root.requestedSection) < root.sectionKeys.length - 1)
                root.movingSection = root.requestedSection;
            fadeOut.duration = root.shownSection === "" ? 0 : root.sectionFadeMs;
            slideOut.duration = root.movingSection === "" ? 0 : root.sectionFadeMs;
            collapseSlot.duration = collapseDrawer.duration = root.movingSection === "" ? 0 : root.sectionFoldMs;
            slideIn.duration = root.movingSection === "" ? 0 : root.sectionFadeMs;
            fadeIn.duration = root.requestedSection === "" ? 0 : root.sectionFadeMs;
            sectionTransition.start();
        } else
            root.heldListHeight = -1;
    }

    SequentialAnimation {
        id: sectionTransition
        onFinished: {
            for (const part of list.children)
                if (part.forceLayout)
                    part.forceLayout();
            list.forceLayout();
            viewportResize.from = root.heldListHeight;
            viewportResize.to = Math.min(list.implicitHeight, root.listMax);
            viewportResize.start();
        }

        ParallelAnimation {
            NumberAnimation {
                id: fadeOut
                target: root
                property: "sectionOpacity"
                to: 0
                easing.type: Easing.InOutCubic
            }
            NumberAnimation {
                id: slideOut
                target: root
                property: "headerOffset"
                to: -root.bodyWidth
                easing.type: Easing.InOutCubic
            }
        }
        ParallelAnimation {
            NumberAnimation {
                id: collapseSlot
                target: root
                property: "headerExpansion"
                to: 0
                easing.type: Easing.InOutCubic
            }
            NumberAnimation {
                id: collapseDrawer
                target: root
                property: "sectionExpansion"
                to: 0
                easing.type: Easing.InOutCubic
            }
        }
        ScriptAction {
            script: {
                root.moveSectionLast(root.requestedSection);
                root.sectionExpansion = 0;
                root.shownSection = root.requestedSection;
                root.sectionOpacity = 0;
                root.headerExpansion = 1;
                root.headerOffset = root.movingSection === "" ? 0 : -root.bodyWidth;
            }
        }
        NumberAnimation {
            id: slideIn
            target: root
            property: "headerOffset"
            to: 0
            easing.type: Easing.InOutCubic
        }
        ScriptAction { script: root.sectionExpansion = 1 }
        NumberAnimation {
            id: fadeIn
            target: root
            property: "sectionOpacity"
            from: 0
            to: 1
            easing.type: Easing.InOutCubic
        }
        ScriptAction { script: root.movingSection = "" }
    }

    NumberAnimation {
        id: viewportResize
        target: root
        property: "heldListHeight"
        duration: root.sectionFoldMs
        easing.type: Easing.InOutCubic
        onFinished: root.heldListHeight = -1
    }

    readonly property var sections: [{ section: "videos", title: "YouTube", videos: Feeds.unseenVideos, stories: [] }]
            .concat(Feeds.unseenSources.map(s => ({ section: s.url, title: s.title, videos: [], stories: s.items })))
            .filter(s => s.videos.length + s.stories.length > 0)
    readonly property var sectionOrder: root.sectionKeys.map(key => root.sections.find(s => s.section === key))
        .filter(s => s !== undefined)

    onVisibleChanged: {
        Feeds.undos = [];
        root.updateSection();
        if (root.visible)
            Feeds.checkHistory();
    }
    Component.onDestruction: Feeds.undos = []

    PopupHeader {
        id: feedHeader

        width: root.bodyWidth
        // Over the rows, which run on under it (ScrollUnder).
        z: 1
        title: "Feeds"
        addable: Feeds.count > 0
        addGlyph: Theme.glyph.checkAll
        addLabel: "Clear"
        addName: "Mark All Seen"
        onAdd: Feeds.markAllSeen()

        // YouTube's own sign-in (YouTubeAccount), not the mail one: the
        // subscriptions can be a brand account's.
        PopupButton {
            visible: !Feeds.connected
            live: !YouTubeAccount.consenting
            framed: true
            glyph: Theme.glyph.reconnect
            label: YouTubeAccount.configured ? "Reconnect" : "Connect YouTube"
            warn: YouTubeAccount.configured
            onTapped: {
                OpenPopup.dismiss();
                YouTubeAccount.reconsent();
            }
        }

        RetryButton { service: Feeds }

        // Takes back the latest swipe, or the Mark All Seen.
        PopupButton {
            visible: Feeds.undos.length > 0
            framed: true
            glyph: Theme.glyph.undo
            label: "Undo"
            onTapped: Feeds.undo()
        }

        PopupButton {
            framed: true
            glyph: Theme.glyph.openApp
            name: "Open YouTube"
            onTapped: Feeds.openApp()
        }
    }

    PopupNote {
        id: troubleNote

        width: root.bodyWidth
        visible: Feeds.trouble !== "" && Feeds.trouble !== YouTubeAccount.reconnect
        text: Feeds.trouble
        warn: true
    }

    PopupNote {
        id: emptyNote

        width: root.bodyWidth
        visible: !Feeds.connected || !Feeds.loaded || Feeds.count === 0
        text: !Feeds.connected ? (YouTubeAccount.configured ? "YouTube needs reconnecting." : "Connect the account or channel that holds your subscriptions.")
            : !Feeds.loaded ? Feeds.tooltip : "Nothing new"
    }

    Flickable {
        id: view

        Accessible.role: Accessible.List
        Accessible.name: "Feeds"
        Accessible.onScrollUpAction: contentY = Math.max(originY, contentY - height / 2)
        Accessible.onScrollDownAction: contentY = Math.min(originY + Math.max(0, contentHeight - height), contentY + height / 2)

        width: root.bodyWidth
        height: root.heldListHeight >= 0 ? root.heldListHeight : Math.min(list.implicitHeight, root.listMax)
        visible: Feeds.count > 0
        contentHeight: list.implicitHeight
        clip: true

        ScrollUnder {
            parent: view
            view: view
            box: root.chromeItem
            // The held viewport ends at a feed header until its resize finishes.
            bottomReach: root.heldListHeight >= 0 ? 0 : Theme.scrollEdge
        }
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        SmoothScroll { view: view }
        acceptedButtons: Qt.NoButton

        Column {
            id: list

            width: parent.width
            spacing: root.rowGap

            Repeater {
                // Stable keys preserve delegates when an opened feed moves last.
                model: ScriptModel {
                    values: root.sectionOrder.map(s => s.section)
                }

                delegate: Column {
                    id: part

                    required property string modelData
                    readonly property var source: root.sections.find(s => s.section === part.modelData)
                        ?? { title: "", videos: [], stories: [] }
                    readonly property bool shown: root.shownSection === part.modelData
                    property int storyLimit: Feeds.storiesShown

                    width: root.bodyWidth
                    height: implicitHeight * (root.movingSection === part.modelData ? root.headerExpansion : 1)
                    clip: true
                    spacing: 0
                    z: part.shown ? 1 : 0

                    Fold {
                        id: fold
                        x: root.movingSection === part.modelData ? root.headerOffset : 0
                        section: part.modelData
                        title: part.source.title
                        unseen: part.source.videos.length + part.source.stories.length
                    }

                    Item {
                        id: reveal

                        width: parent.width
                        height: part.shown ? (rows.implicitHeight + root.rowGap) * root.sectionExpansion : 0
                        clip: true
                        enabled: fold.open && !sectionTransition.running
                        opacity: root.sectionOpacity
                        layer.enabled: opacity > 0 && opacity < 1

                        Column {
                            id: rows

                            y: root.rowGap
                            width: parent.width
                            spacing: root.rowGap

                            Repeater {
                                model: part.shown ? part.source.videos : []
                                delegate: videoRow
                            }

                            Repeater {
                                model: part.shown ? part.source.stories.slice(0, part.storyLimit) : []
                                delegate: storyRow
                            }

                            PopupRow {
                                name: "Load More"
                                width: root.bodyWidth
                                height: moreLabel.implicitHeight + root.rowPad * 2
                                visible: part.shown && part.source.stories.length > part.storyLimit
                                gesturePolicy: TapHandler.ReleaseWithinBounds
                                onTapped: part.storyLimit += Feeds.storiesShown

                                HoverHandler { cursorShape: Qt.PointingHandCursor }

                                PopupText {
                                    id: moreLabel
                                    x: root.inset
                                    y: root.rowPad
                                    text: "Load More"
                                    color: Theme.label2
                                    font.pixelSize: Theme.footnoteSize
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: videoRow

        SwipeRow {
            id: video

            required property var modelData

            name: video.modelData.title
            width: root.bodyWidth
            fullHeight: root.thumbHeight + root.rowPad * 2
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: Feeds.open(video.modelData, "")
            onSwiped: Feeds.hide(video.modelData)

            ClippingRectangle {
                x: root.inset + video.swipe
                y: root.rowPad
                width: root.thumbWidth
                height: root.thumbHeight
                radius: Theme.selectionRadius
                color: Theme.well

                Image {
                    anchors.fill: parent
                    source: video.modelData.thumb
                    sourceSize.width: root.thumbWidth * 2
                    sourceSize.height: root.thumbHeight * 2
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    opacity: status === Image.Ready ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.fadeMs
                        }
                    }
                }
            }

            Column {
                x: root.textX + video.swipe
                y: root.rowPad + Math.round((root.thumbHeight - height) / 2)
                width: parent.width - root.textX - root.inset
                spacing: 1

                PopupText {
                    width: parent.width
                    text: video.modelData.title
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: Theme.captionSize
                    font.weight: Font.DemiBold
                }

                PopupText {
                    width: parent.width
                    text: [video.modelData.channel, video.modelData.duration >= 0 ? Feeds.clock(video.modelData.duration) : "",
                        Feeds.age(video.modelData.published, root.now)].filter(s => s !== "").join(" · ")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.label2
                    font.pixelSize: Theme.footnoteSize
                }
            }
        }
    }

    Component {
        id: storyRow

        SwipeRow {
            id: story

            required property var modelData
            readonly property int textInset: thumbnail.visible ? root.textX : root.inset
            readonly property var facts: [
                story.modelData.points >= 0 ? `${story.modelData.points} points` : "",
                story.modelData.replies >= 0 ? `${story.modelData.replies} comments` : "",
                Feeds.age(story.modelData.published, root.now)
            ].filter(s => s !== "")

            name: story.modelData.title
            width: root.bodyWidth
            fullHeight: Math.max(lines.implicitHeight, thumbnail.visible ? root.thumbHeight : 0) + root.rowPad * 2
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: Feeds.open(story.modelData, "")
            onSwiped: Feeds.hide(story.modelData)

            ClippingRectangle {
                id: thumbnail

                x: root.inset + story.swipe
                y: root.rowPad
                width: root.thumbWidth
                height: root.thumbHeight
                visible: (story.modelData.thumb ?? "") !== "" && artwork.status !== Image.Error
                radius: Theme.selectionRadius
                color: Theme.well

                Image {
                    id: artwork

                    anchors.fill: parent
                    source: story.modelData.thumb ?? ""
                    sourceSize.width: root.thumbWidth * 2
                    sourceSize.height: root.thumbHeight * 2
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    opacity: status === Image.Ready ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: Theme.fadeMs }
                    }
                }
            }

            Column {
                id: lines

                x: story.textInset + story.swipe
                y: root.rowPad
                width: parent.width - story.textInset - root.inset
                spacing: 1

                PopupText {
                    width: parent.width
                    text: story.modelData.title
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: Theme.captionSize
                    font.weight: Font.DemiBold
                }

                PopupText {
                    width: parent.width
                    visible: text !== ""
                    text: story.modelData.summary ?? ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    color: Theme.label2
                    font.pixelSize: Theme.footnoteSize
                }

                PopupText {
                    width: parent.width
                    text: story.facts.join(" · ")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.label2
                    font.pixelSize: Theme.footnoteSize
                }
            }
        }
    }

    // A part's header: its name and how many in it are new. A click opens
    // or folds it; folded is how each starts, so the popup opens as a short
    // stack of these, and Feeds remembers the one left open.
    component Fold: PopupRow {
        id: fold

        property string section: ""
        property string title: ""
        property int unseen: 0
        readonly property bool open: Feeds.unfolded(fold.section)

        name: (fold.open ? "Fold " : "Show ") + fold.title
        width: root.bodyWidth
        height: heading.implicitHeight + root.rowPad * 2
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: Feeds.toggle(fold.section)

        Glyph {
            x: root.inset
            anchors.verticalCenter: parent.verticalCenter
            text: Theme.glyph.sectionShut
            rotation: fold.open ? 90 : 0
            fontSize: Theme.footnoteSize
            color: Theme.label2

            Behavior on rotation {
                NumberAnimation {
                    duration: Settings.reduceMotion ? 0 : root.sectionFoldMs
                    easing.type: Easing.InOutCubic
                }
            }
        }

        PopupText {
            id: heading
            x: root.inset + 16
            y: root.rowPad
            width: tally.x - x - 8
            text: fold.title
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.label2
            font.pixelSize: Theme.captionSize
            font.weight: Font.DemiBold
        }

        PopupText {
            id: tally
            anchors.right: parent.right
            anchors.rightMargin: root.inset
            anchors.baseline: heading.baseline
            text: fold.unseen
            font.pixelSize: Theme.footnoteSize
            color: Theme.label2
        }
    }
}

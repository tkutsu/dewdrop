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
// back the swipes (and "Mark All Seen") until the popup closes. A story's
// discussion is the button on its row.
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
    // Ages move on the minute.
    readonly property real now: Google.now.getTime()
    readonly property string requestedSection: root.sections.find(s => Feeds.unfolded(s.section))?.section ?? ""
    property string shownSection: ""
    property real sectionOpacity: 1
    property bool sectionReady: false

    onRequestedSectionChanged: root.updateSection()
    Component.onCompleted: {
        root.sectionReady = true;
        root.updateSection();
    }

    // Keep the outgoing drawer still until it is invisible, then lay out the next.
    function updateSection(): void {
        if (!root.sectionReady)
            return;
        sectionTransition.stop();
        if (Settings.reduceMotion || !root.visible) {
            root.shownSection = root.requestedSection;
            root.sectionOpacity = 1;
        } else if (root.shownSection !== root.requestedSection || root.sectionOpacity < 1) {
            fadeOut.duration = root.shownSection === "" ? 0 : Theme.fadeMs;
            sectionTransition.start();
        }
    }

    SequentialAnimation {
        id: sectionTransition

        NumberAnimation {
            id: fadeOut
            target: root
            property: "sectionOpacity"
            to: 0
            easing.type: Easing.InOutCubic
        }
        ScriptAction { script: root.shownSection = root.requestedSection }
        NumberAnimation {
            target: root
            property: "sectionOpacity"
            to: 1
            duration: root.requestedSection === "" ? 0 : Theme.fadeMs
            easing.type: Easing.InOutCubic
        }
    }

    readonly property var sections: [{ section: "videos", title: "YouTube", videos: Feeds.unseenVideos, stories: [] }]
            .concat(Feeds.unseenSources.map(s => ({ section: s.url, title: s.title, videos: [], stories: s.items })))
            .filter(s => s.videos.length + s.stories.length > 0)
    // Reorder only after the outgoing drawer has faded away.
    readonly property var sectionOrder: root.sections.filter(s => s.section !== root.shownSection)
        .concat(root.sections.filter(s => s.section === root.shownSection))

    onVisibleChanged: {
        Feeds.undos = [];
        root.updateSection();
        if (root.visible)
            Feeds.checkHistory();
    }
    Component.onDestruction: Feeds.undos = []

    PopupHeader {
        width: root.bodyWidth
        // Over the rows, which run on under it (ScrollUnder).
        z: 1
        title: "Feeds"

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
            visible: Feeds.count > 0
            framed: true
            glyph: Theme.glyph.checkAll
            label: "Mark All Seen"
            onTapped: Feeds.markAllSeen()
        }

        PopupButton {
            framed: true
            glyph: Theme.glyph.openApp
            name: "Open YouTube"
            onTapped: Feeds.openApp()
        }
    }

    PopupNote {
        width: root.bodyWidth
        visible: Feeds.trouble !== "" && Feeds.trouble !== YouTubeAccount.reconnect
        text: Feeds.trouble
        warn: true
    }

    PopupNote {
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
        height: Math.min(list.implicitHeight, root.listMax)
        visible: Feeds.count > 0
        contentHeight: list.implicitHeight
        clip: true

        ScrollUnder {
            parent: view
            view: view
            box: root.chromeItem
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
                // Stable keys preserve delegates when closed headers move up.
                model: ScriptModel {
                    values: root.sectionOrder.map(s => s.section)
                }

                delegate: Column {
                    id: part

                    required property string modelData
                    readonly property var source: root.sections.find(s => s.section === part.modelData)
                        ?? { title: "", videos: [], stories: [] }
                    readonly property bool shown: root.shownSection === part.modelData

                    width: root.bodyWidth
                    spacing: 0
                    z: part.shown ? 1 : 0

                    Fold {
                        id: fold
                        section: part.modelData
                        title: part.source.title
                        unseen: part.source.videos.length + part.source.stories.length
                    }

                    Item {
                        id: reveal

                        width: parent.width
                        height: part.shown ? rows.implicitHeight + root.rowGap : 0
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
                                model: part.shown ? part.source.stories : []
                                delegate: storyRow
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
                    text: [video.modelData.channel, Feeds.clock(video.modelData.duration), Feeds.age(video.modelData.published, root.now)].join(" · ")
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
            readonly property var facts: [
                story.modelData.points >= 0 ? `${story.modelData.points} points` : "",
                story.modelData.replies >= 0 ? `${story.modelData.replies} comments` : "",
                Feeds.age(story.modelData.published, root.now)
            ].filter(s => s !== "")

            name: story.modelData.title
            width: root.bodyWidth
            fullHeight: lines.implicitHeight + root.rowPad * 2
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: Feeds.open(story.modelData, "")
            onSwiped: Feeds.hide(story.modelData)

            Column {
                id: lines

                x: root.inset + story.swipe
                y: root.rowPad
                width: parent.width - root.inset * 2 - (talk.visible ? talk.width + 4 : 0)
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
                    text: story.facts.join(" · ")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.label2
                    font.pixelSize: Theme.footnoteSize
                }
            }

            PopupButton {
                id: talk

                anchors.right: parent.right
                anchors.rightMargin: root.inset - story.swipe
                anchors.verticalCenter: parent.verticalCenter
                visible: story.hovered && !story.swiping && story.modelData.comments !== ""
                glyph: Theme.glyph.comments
                name: "Comments"
                onTapped: Feeds.open(story.modelData, story.modelData.comments)
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
                    duration: Settings.reduceMotion ? 0 : Theme.foldMs
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

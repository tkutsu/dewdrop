import QtQuick
import Quickshell.Widgets
import qs
import qs.components
import qs.services

// The week's videos from the channels followed, then each feed's stories,
// newest first. New ones are bright until opened; a click opens one in the
// browser and counts it seen, and "Mark All Seen" clears the badge without
// opening anything. A story's discussion is the button on its row.
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
        visible: !Feeds.connected || !Feeds.loaded || (Feeds.videos.length === 0 && Feeds.sources.length === 0)
        text: !Feeds.connected ? (YouTubeAccount.configured ? "YouTube needs reconnecting." : "Connect the account or channel that holds your subscriptions.")
            : !Feeds.loaded ? Feeds.tooltip : "Nothing this week"
    }

    Flickable {
        id: view

        Accessible.role: Accessible.List
        Accessible.name: "Feeds"
        Accessible.onScrollUpAction: contentY = Math.max(originY, contentY - height / 2)
        Accessible.onScrollDownAction: contentY = Math.min(originY + Math.max(0, contentHeight - height), contentY + height / 2)

        width: root.bodyWidth
        height: Math.min(list.implicitHeight, root.listMax)
        visible: Feeds.videos.length > 0 || Feeds.sources.length > 0
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

            PopupSection {
                width: root.bodyWidth
                visible: Feeds.videos.length > 0
                ruled: false
                title: "Videos"
            }

            Repeater {
                model: Feeds.videos

                delegate: PopupRow {
                    id: video

                    required property var modelData
                    readonly property bool fresh: Feeds.unread(video.modelData)

                    name: video.modelData.title
                    width: root.bodyWidth
                    height: root.thumbHeight + root.rowPad * 2
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: Feeds.open(video.modelData, "")

                    ClippingRectangle {
                        x: root.inset
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
                            opacity: status === Image.Ready ? (video.fresh ? 1 : 0.6) : 0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Theme.fadeMs
                                }
                            }
                        }
                    }

                    Column {
                        x: root.textX
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - root.textX - root.inset
                        spacing: 1

                        PopupText {
                            width: parent.width
                            text: video.modelData.title
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: video.fresh ? Theme.fg : Theme.label2
                            font.pixelSize: Theme.captionSize
                            font.weight: video.fresh ? Font.DemiBold : Font.Normal
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

            Repeater {
                model: Feeds.sources

                delegate: Column {
                    id: source

                    required property var modelData
                    required property int index

                    width: root.bodyWidth
                    spacing: root.rowGap

                    PopupSection {
                        width: root.bodyWidth
                        ruled: Feeds.videos.length > 0 || source.index > 0
                        title: source.modelData.title
                    }

                    Repeater {
                        model: source.modelData.items

                        delegate: PopupRow {
                            id: story

                            required property var modelData
                            readonly property bool fresh: Feeds.unread(story.modelData)
                            readonly property var facts: [
                                story.modelData.points >= 0 ? `${story.modelData.points} points` : "",
                                story.modelData.replies >= 0 ? `${story.modelData.replies} comments` : "",
                                Feeds.age(story.modelData.published, root.now)
                            ].filter(s => s !== "")

                            name: story.modelData.title
                            width: root.bodyWidth
                            height: lines.implicitHeight + root.rowPad * 2
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: Feeds.open(story.modelData, "")

                            Column {
                                id: lines

                                x: root.inset
                                y: root.rowPad
                                width: parent.width - root.inset * 2 - (talk.visible ? talk.width + 4 : 0)
                                spacing: 1

                                PopupText {
                                    width: parent.width
                                    text: story.modelData.title
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: story.fresh ? Theme.fg : Theme.label2
                                    font.pixelSize: Theme.captionSize
                                    font.weight: story.fresh ? Font.DemiBold : Font.Normal
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
                                anchors.rightMargin: root.inset
                                anchors.verticalCenter: parent.verticalCenter
                                visible: story.hovered && story.modelData.comments !== ""
                                glyph: Theme.glyph.comments
                                name: "Comments"
                                onTapped: Feeds.open(story.modelData, story.modelData.comments)
                            }
                        }
                    }
                }
            }
        }
    }
}

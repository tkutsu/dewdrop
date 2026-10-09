import QtQuick
import QtQuick.Effects
import qs
import qs.components
import qs.services

// Everything the mpd tooltip's five lines of text were reaching for: the cover,
// a position that can be dragged rather than only read, the transport, the
// player's own volume, and the queue MPD is working through — which can be
// played from, reordered and cut down without opening the player it belongs to.
Popup {
    id: root

    readonly property int columnWidth: 290
    // The two tracks run between the same two points: an icon's width of
    // gutter on the left, a readout's on the right. The volume has something
    // to put in the gutter and the position has not, which is not a reason for
    // the two of them to start in different places.
    readonly property int gutter: 16
    // The pill's colour for the track, taken off the sleeve (Music.accent),
    // so the position here is the same line as the one round the pill.
    property color accent: Theme.fg
    // Wide enough for both figures of the longest track anyone is likely to
    // queue, so the track beside it does not shorten as the numbers grow.
    readonly property int readoutWidth: 84
    readonly property int sliderWidth: columnWidth - gutter - readoutWidth - 12
    // The cover squares off against the column beside it rather than being
    // given a size of its own, so the header is one block however many lines
    // the column turns out to have.
    // The foot of the artwork, which the transport stands in.
    readonly property int transportBand: 26
    // Tall enough that the band is the foot of a picture rather than a third
    // of one, for the albums that come with no picture at all and for the
    // short column an mpd with no mixer leaves beside them.
    readonly property int minArtSize: 84
    readonly property int artSize: Math.max(minArtSize, Math.ceil(info.implicitHeight))
    // One width for the header, the rule and the rows, so all three stop in the
    // same place.
    readonly property int bodyWidth: artSize + 10 + columnWidth

    // Tighter than the header's lines: a queue is read as a block rather than
    // line by line, and eight of these is about as much of one as can be taken
    // in without it becoming a window of its own.
    readonly property int rowHeight: 22
    readonly property int visibleRows: 8

    // Give row controls a full hit target around their glyphs.
    readonly property int buttonWidth: 20
    readonly property int queueTailWidth: 60

    // Whether the quit button in the header has been pressed once. See the
    // button itself for why it takes two.
    property bool quitArmed: false

    spacing: 8

    // The window is always the height of the popup with the playlists
    // unfolded, so folding them only redraws inside it (see Popup.reserveHeight).
    reserveHeight: chromeHeight + (Mpd.playlistsOpen ? 0 : Mpd.playlists.length * rowHeight)

    Row {
        spacing: 10

        Rectangle {
            width: root.artSize
            height: root.artSize
            color: Theme.well

            Image {
                id: cover
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                source: Mpd.cover
                sourceSize.width: 192
                sourceSize.height: 192
            }

            // The transport, on the cover rather than under the column beside
            // it. The three of them were a row of their own at the bottom of
            // the popup, which is a row of its own worth of height for the
            // three controls least in need of the room — and the picture is
            // already the thing the pointer goes to.
            //
            // A band shading into the foot of the artwork, because the glyphs
            // are white and the artwork underneath them is whatever it is.
            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                height: root.transportBand

                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 1
                        color: Theme.scrim
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 10

                    Repeater {
                        model: [
                            {
                                name: "Previous track",
                                glyph: Theme.glyph.mediaPrev,
                                act: () => Mpd.prev()
                            },
                            {
                                name: Mpd.state === "play" ? "Pause music" : "Play music",
                                glyph: Mpd.state === "play" ? Theme.glyph.paused : Theme.glyph.playing,
                                act: () => Mpd.toggle()
                            },
                            {
                                name: "Next track",
                                glyph: Theme.glyph.mediaNext,
                                act: () => Mpd.next()
                            }
                        ]

                        delegate: Glyph {
                            required property var modelData

                            text: modelData.glyph
                            fontSize: Theme.glyphSizeLarge
                            implicitHeight: root.transportBand
                            opacity: press.hovered ? 1 : 0.8

                            HoverHandler {
                                id: press
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.name
                            Accessible.onPressAction: if (enabled && visible)
                                modelData.act()

                            TapHandler {
                                onTapped: parent.modelData.act()
                            }
                        }
                    }
                }
            }
        }

        Column {
            id: info

            spacing: 3

            // The title shares its line with the one control here that is not
            // about the music: putting mpd itself down. Top right, as far from
            // the transport on the cover as the popup goes — the buttons that
            // move the music and the button that ends it have no business
            // being neighbours.
            Item {
                width: root.columnWidth
                height: songTitle.implicitHeight

                PopupText {
                    id: songTitle

                    anchors {
                        left: parent.left
                        right: add.left
                        rightMargin: 6
                        verticalCenter: parent.verticalCenter
                    }
                    text: Mpd.title
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                // The way to put something else on: the launcher's # mode,
                // which has the whole library. Beside the quit button, as
                // every popup under the bar keeps its plus at the right end of
                // its top line; the quit button asks twice, so a plus that
                // misses does not end anything.
                PopupButton {
                    id: add
                    name: "Choose music"

                    anchors.right: quit.left
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    framed: true
                    glyph: Theme.glyph.plus
                    onTapped: Launcher.openWith(Launcher.musicPrefix)
                }

                // Asked twice. Everything else in this popup can be undone
                // from this popup; this cannot — mpd going down takes the
                // pill the popup hangs from with it, so the second press is
                // the last chance to reconsider. Arming lasts until this
                // popup closes or the second press stops MPD.
                PopupButton {
                    id: quit
                    name: root.quitArmed ? "Confirm quit music player" : "Quit music player"

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    framed: true
                    glyph: root.quitArmed ? Theme.glyph.check : Theme.glyph.close
                    warn: root.quitArmed
                    onTapped: {
                        if (root.quitArmed)
                            Mpd.stopServer();
                        else
                            root.quitArmed = true;
                    }
                }
            }

            PopupText {
                width: root.columnWidth
                text: [Mpd.artist, Mpd.album].filter(part => part).join("  ·  ")
                opacity: 0.75
                elide: Text.ElideRight
            }

            Item {
                width: 1
                height: 3
            }

            // How far through, twice over: the track says how far, the figures
            // say how far in what. They were a row apart from each other and
            // are one reading.
            Row {
                spacing: 6

                // One control for three states rather than repeat and single
                // as separate toggles: what is being asked is how far playback
                // goes back round — nowhere, the queue, or this song — which
                // is one question with three answers, and it belongs against
                // the track it is a question about.
                Item {
                    width: root.gutter
                    height: Theme.popupTextSize + 4

                    Glyph {
                        anchors.centerIn: parent
                        text: Mpd.repeatIcon
                        fontSize: Theme.captionSize
                        implicitHeight: parent.height
                        opacity: Mpd.repeatMode === "off" ? 0.3 : 1
                    }

                    // On the box rather than on the glyph: the ink is eight
                    // pixels of arrow and the box is the whole gutter.
                    Accessible.role: Accessible.Button
                    Accessible.name: "Repeat mode: " + Mpd.repeatMode
                    Accessible.onPressAction: if (enabled && visible)
                        Mpd.cycleRepeat()

                    TapHandler {
                        onTapped: Mpd.cycleRepeat()
                    }
                }

                Slider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.sliderWidth
                    name: "Playback position"
                    value: Mpd.duration > 0 ? Mpd.elapsed / Mpd.duration : 0
                    // A stream has no length to seek through.
                    enabled: Mpd.duration > 0
                    knob: false
                    fill: root.accent
                    // Ten seconds a notch, as on the pill.
                    wheelStep: Mpd.duration > 0 ? 10 / Mpd.duration : 0
                    onMoved: value => Mpd.seekTo(value)
                }

                PopupText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.readoutWidth
                    horizontalAlignment: Text.AlignRight
                    text: Mpd.duration > 0 ? `${Mpd.clock(Mpd.elapsed)} / ${Mpd.clock(Mpd.duration)}` : Mpd.clock(Mpd.elapsed)
                    opacity: 0.75
                    font.pixelSize: Theme.captionSize
                }
            }

            // mpd's own level, not the system's — the bar's audio module is two
            // pills along for that. They are different questions: how loud the
            // music is against everything else, and how loud everything is.
            Row {
                spacing: 6
                visible: Mpd.volume >= 0

                Item {
                    width: root.gutter
                    height: Theme.popupTextSize + 4

                    Glyph {
                        anchors.centerIn: parent
                        text: Mpd.volumeIcon
                        fontSize: Theme.captionSize
                        implicitHeight: parent.height
                        // Lit while it is the thing standing between you and
                        // the music, quiet while it is only a label for the
                        // track beside it.
                        opacity: Mpd.volume > 0 ? 0.75 : 1
                    }

                    Accessible.role: Accessible.Button
                    Accessible.name: "Toggle music mute"
                    Accessible.onPressAction: if (enabled && visible)
                        Mpd.toggleMute()

                    TapHandler {
                        onTapped: Mpd.toggleMute()
                    }
                }

                Slider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.sliderWidth
                    name: "Music volume"
                    value: Math.max(0, Mpd.volume) / 100
                    wheelStep: 0.05
                    onMoved: value => Mpd.setVolume(value)
                }

                PopupText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.readoutWidth
                    horizontalAlignment: Text.AlignRight
                    text: Math.max(0, Mpd.volume) + "%"
                    opacity: 0.75
                    font.pixelSize: Theme.captionSize
                }
            }

        }
    }

    // The stored playlists, folded away under one line.
    //
    // Folded because they are the thing here you reach for least: the queue
    // below is what the popup is for, and a shelf of saved queues unrolled
    // above it every time would push the thing being looked at down the
    // screen for the sake of the thing that is not. One line is what it costs
    // shut, which is about what it is worth.
    //
    // Whether it is open lives on the service rather than here, for the same
    // reason Mpd.premute does: the popup is rebuilt each time it opens,
    // while this preference lasts for the session.
    Column {
        width: root.bodyWidth
        spacing: 0
        // Nothing saved, nothing to say.
        visible: Mpd.playlists.length > 0

        Rectangle {
            width: root.bodyWidth
            height: Theme.pillBorder
            color: Theme.stroke
        }

        PopupRow {
            id: head
            name: "Show playlists"

            width: root.bodyWidth
            height: root.rowHeight

            // The whole line folds it, not the chevron: the mark is eight
            // pixels of ink and the line is the width of the popup.
            onTapped: Mpd.playlistsOpen = !Mpd.playlistsOpen

            Glyph {
                id: fold

                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: Mpd.playlistsOpen ? Theme.glyph.sectionOpen : Theme.glyph.sectionShut
                fontSize: Theme.footnoteSize
                implicitHeight: root.rowHeight
                opacity: 0.5
            }

            PopupText {
                id: headLabel

                anchors.left: fold.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "playlists"
                font.pixelSize: Theme.captionSize
                opacity: 0.8
            }

            PopupText {
                anchors.left: headLabel.right
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: String(Mpd.playlists.length)
                font.pixelSize: Theme.footnoteSize
                opacity: 0.4
            }
        }

        Repeater {
            model: Mpd.playlistsOpen ? Mpd.playlists : []

            // Deliberately no tap on the row itself, where a queue row plays
            // the song under the pointer. The two things you might mean here
            // are adding a playlist to what is on and throwing away what is on
            // for it, and no reading of a click on the name picks between them
            // — least of all one that can lose a queue somebody spent the
            // evening building.
            delegate: PopupRow {
                id: entry

                required property string modelData

                width: root.bodyWidth
                height: root.rowHeight

                readonly property bool armed: Mpd.armedPlaylist === entry.modelData

                // Leaving the row is how a half-pressed delete is called off.
                // There is no cancel button because there does not need to be
                // one: the way out is the direction the pointer was going.
                onHoveredChanged: if (!entry.hovered && entry.armed)
                    Mpd.armedPlaylist = ""

                PopupText {
                    anchors {
                        left: parent.left
                        // Past the fold mark above, so the names read as what
                        // is inside the section rather than as more of its
                        // heading.
                        leftMargin: 6 + 16
                        right: buttons.left
                        rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    text: entry.modelData
                    font.pixelSize: Theme.captionSize
                    opacity: 0.8
                    elide: Text.ElideRight
                }

                // All three, always, rather than one default and two
                // alternates: adding a playlist to what is on, throwing away
                // what is on for it and throwing away the playlist itself are
                // three different things, and a row of saved queues is where
                // the difference between them matters most.
                Row {
                    id: buttons

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: root.rowHeight
                    spacing: 0
                    visible: entry.hovered

                    Repeater {
                        model: [
                            {
                                name: "Queue " + entry.modelData,
                                glyph: Theme.glyph.playlistAppend,
                                live: !entry.armed,
                                warn: false,
                                act: () => Mpd.loadPlaylist(entry.modelData, "queue")
                            },
                            {
                                name: "Play " + entry.modelData,
                                glyph: Theme.glyph.playlistLoad,
                                live: !entry.armed,
                                warn: false,
                                act: () => Mpd.loadPlaylist(entry.modelData, "play")
                            },
                            {
                                // Asked, and then asked again. The mark
                                // changes with the question: a list with a
                                // cross on it is "delete this", and the tick
                                // that replaces it is "yes, that" — the same
                                // pair the power menu puts up before it turns
                                // the machine off.
                                name: (entry.armed ? "Confirm delete " : "Delete ") + entry.modelData,
                                glyph: entry.armed ? Theme.glyph.powerConfirm : Theme.glyph.playlistRemove,
                                live: true,
                                warn: entry.armed,
                                act: () => {
                                    if (entry.armed)
                                        Mpd.removePlaylist(entry.modelData);
                                    else
                                        Mpd.armedPlaylist = entry.modelData;
                                }
                            }
                        ]

                        // Armed, the other two go quiet where they stand
                        // rather than making way: three buttons becoming one
                        // would slide the answer under a pointer already on
                        // its way to it.
                        delegate: PopupButton {
                            required property var modelData

                            width: root.buttonWidth
                            height: root.rowHeight
                            name: modelData.name
                            glyph: modelData.glyph
                            live: modelData.live
                            warn: modelData.warn
                            onTapped: modelData.act()
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        width: root.bodyWidth
        height: Theme.pillBorder
        color: Theme.stroke
        visible: list.count > 0
    }

    ListView {
        id: list

        width: root.bodyWidth
        // A short queue draws short rather than padding itself out with empty
        // rows, the same way the launcher's list does.
        height: Math.min(count, root.visibleRows) * root.rowHeight
        clip: true
        model: reorder.showing ? reorder.queue : Mpd.queue
        interactive: !reorder.showing
        // Nothing here scrolls with momentum; a flick that overshoots the ends
        // only looks like the list came loose.
        boundsBehavior: Flickable.StopAtBounds

        // The song playing is the one you came here from, so that is where the
        // queue opens — not at the top of a hundred songs you have been
        // through already. Deferred because the view has no rows to position
        // itself on until it has been laid out once.
        Component.onCompleted: Qt.callLater(() => {
            if (Mpd.songPos < 0)
                return;
            list.positionViewAtIndex(Mpd.songPos, ListView.Center);
            // Whole rows only. Centring a row in an even number of them lands
            // half a row out, and a row sliced by the rule above it reads as a
            // mistake rather than as the queue carrying on past the edge.
            list.contentY = Math.max(0, Math.min(list.contentHeight - list.height, Math.round(list.contentY / root.rowHeight) * root.rowHeight));
        })

        Connections {
            target: Mpd

            // The model is a plain array and is replaced whole on every
            // refresh, which puts the view back at the top with it. Removing a
            // song should not cost you your place in the queue it came out of.
            function onQueueChanging() {
                const y = list.contentY;
                Qt.callLater(() => {
                    list.contentY = Math.max(0, Math.min(list.contentHeight - list.height, y));
                });
            }

            function onQueueChanged() {
                if (reorder.settling && !drop.running)
                    reorder.finishDrop();
            }
        }

        // Keep the pointer grab on the view: MPD replaces whole arrays, and
        // scrolling can recycle the row that started the drag.
        MouseArea {
            id: reorder

            parent: list
            anchors.fill: parent
            z: 2
            enabled: !settling
            acceptedButtons: Qt.LeftButton
            pressAndHoldInterval: 300
            preventStealing: dragging
            cursorShape: dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor

            property bool dragging: false
            property bool settling: false
            readonly property bool showing: dragging || settling
            property real elevation: 0
            property real dropY: 0
            property var queue: []
            property int from: -1
            property int to: -1
            property real grabOffset: 0
            readonly property real liftedY: Math.max(0, Math.min(height - root.rowHeight, mouseY - grabOffset))
            readonly property int scrollDirection: !dragging ? 0 : mouseY < root.rowHeight ? -1 : mouseY > height - root.rowHeight ? 1 : 0

            // Use the lifted row's centre to choose the slot, including rows
            // reached by scrolling while the pointer stays at an edge.
            function updateTarget() {
                if (dragging)
                    to = Math.max(0, Math.min(queue.length - 1, Math.floor((list.contentY + liftedY + root.rowHeight / 2) / root.rowHeight)));
            }

            // Switching back to MPD's model rebuilds the view after the drop.
            function finishDrop() {
                const y = list.contentY;
                dragging = false;
                settling = false;
                elevation = 0;
                Qt.callLater(() => {
                    list.contentY = Math.max(0, Math.min(Math.max(0, list.contentHeight - list.height), y));
                });
            }

            onPressed: mouse => {
                from = list.indexAt(mouse.x, mouse.y + list.contentY);
                if (from < 0 || mouse.x >= width - root.buttonWidth) {
                    mouse.accepted = false;
                    return;
                }
                queue = Mpd.queue;
                grabOffset = mouse.y + list.contentY - from * root.rowHeight;
            }
            onPressAndHold: {
                if (queue !== Mpd.queue || queue.length < 2)
                    return;
                list.cancelFlick();
                to = from;
                dragging = true;
                elevation = 1;
                updateTarget();
            }
            onPositionChanged: updateTarget()
            onReleased: {
                if (!dragging)
                    return;
                updateTarget();
                // A queue edited elsewhere during the hold has new positions.
                // Cancel rather than moving a different song by a stale index.
                if (queue !== Mpd.queue)
                    to = from;
                else if (from !== to)
                    Mpd.moveTo(queue[from].pos, queue[to].pos);
                dropY = liftedY;
                settling = true;
                dragging = false;
                elevation = 0;
                drop.restart();
            }
            onCanceled: finishDrop()
            onClicked: if (queue === Mpd.queue && from >= 0)
                Mpd.playAt(queue[from].pos)

            Behavior on elevation {
                NumberAnimation {
                    duration: Theme.revealMs
                    easing.type: Easing.OutCubic
                }
            }

            NumberAnimation {
                id: drop
                target: reorder
                property: "dropY"
                to: reorder.to * root.rowHeight - list.contentY
                duration: Theme.revealMs
                easing.type: Easing.OutCubic
                onFinished: {
                    if (reorder.queue !== Mpd.queue || reorder.from === reorder.to)
                        reorder.finishDrop();
                }
            }

            // Keep the landed preview until MPD sends its new order, so a
            // slow reply cannot flash the track back into its old position.
            Timer {
                interval: 1000
                running: reorder.settling && !drop.running
                onTriggered: reorder.finishDrop()
            }

            Timer {
                interval: 100
                repeat: true
                running: reorder.scrollDirection !== 0
                onTriggered: {
                    list.contentY = Math.max(0, Math.min(Math.max(0, list.contentHeight - list.height), list.contentY + reorder.scrollDirection * root.rowHeight));
                    reorder.updateTarget();
                }
            }

            Rectangle {
                id: lifted

                x: 4 * reorder.elevation
                y: (reorder.settling ? reorder.dropY : reorder.liftedY) - 2 * reorder.elevation
                width: parent.width - 8 * reorder.elevation
                height: root.rowHeight
                scale: 1 + 0.01 * reorder.elevation
                visible: reorder.showing
                radius: Theme.selectionRadius
                color: Theme.well
                readonly property var song: reorder.showing ? reorder.queue[reorder.from] : null

                RectangularShadow {
                    anchors.fill: parent
                    z: -1
                    radius: lifted.radius
                    blur: 8
                    offset.y: 3
                    color: Theme.shadow
                    opacity: reorder.elevation
                }

                PopupText {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    horizontalAlignment: Text.AlignRight
                    text: reorder.from === Mpd.songPos ? Mpd.stateIcon : String(reorder.to + 1)
                    font.family: reorder.from === Mpd.songPos ? Theme.glyphFont : Theme.bodyFont
                    font.pixelSize: Theme.footnoteSize
                    opacity: reorder.from === Mpd.songPos ? 1 : 0.4
                }

                Item {
                    id: liftedLine
                    x: 32
                    width: parent.width - x - root.queueTailWidth - 8
                    height: parent.height

                    PopupText {
                        id: liftedName
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, lifted.song?.artist ? liftedLine.width * 0.62 : liftedLine.width)
                        text: lifted.song?.title ?? ""
                        font.pixelSize: Theme.captionSize
                        font.weight: reorder.from === Mpd.songPos ? Font.DemiBold : Font.Normal
                        opacity: reorder.from === Mpd.songPos ? 1 : 0.8
                        elide: Text.ElideRight
                    }

                    PopupText {
                        anchors.left: liftedName.right
                        anchors.leftMargin: 6
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: lifted.song?.artist ?? ""
                        font.pixelSize: Theme.captionSize
                        opacity: 0.45
                        elide: Text.ElideRight
                    }
                }

                PopupText {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: Mpd.clock(lifted.song?.duration ?? 0)
                    font.pixelSize: Theme.footnoteSize
                    opacity: 0.4
                }
            }
        }

        delegate: PopupRow {
            id: row

            required property var modelData
            required property int index

            readonly property bool current: Mpd.songPos === row.index

            name: "Play " + (row.modelData.title || "Track " + (row.index + 1))
            width: ListView.view.width
            height: root.rowHeight
            onTapped: Mpd.playAt(row.modelData.pos)
            opacity: reorder.showing && row.index === reorder.from ? 0 : 1
            transform: Translate {
                y: !reorder.showing ? 0 : row.index > reorder.from && row.index <= reorder.to ? -root.rowHeight : row.index < reorder.from && row.index >= reorder.to ? root.rowHeight : 0

                Behavior on y {
                    enabled: reorder.showing
                    NumberAnimation {
                        duration: Theme.revealMs
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // The queue position, except on the song that is playing — there
            // the number is the one thing you already know, and the state icon
            // is what you came to the list to find.
            PopupText {
                id: ordinal

                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                horizontalAlignment: Text.AlignRight
                text: row.current ? Mpd.stateIcon : String(row.index + 1)
                font.family: row.current ? Theme.glyphFont : Theme.bodyFont
                font.pixelSize: Theme.footnoteSize
                opacity: row.current ? 1 : 0.4
            }

            Item {
                id: line

                anchors {
                    left: ordinal.right
                    leftMargin: 8
                    right: tail.left
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                height: parent.height

                PopupText {
                    id: name

                    anchors.verticalCenter: parent.verticalCenter
                    // The artist keeps its share of the row: two songs of the
                    // same name in a queue are told apart by who plays them.
                    width: Math.min(implicitWidth, row.modelData.artist ? line.width * 0.62 : line.width)
                    text: row.modelData.title
                    font.pixelSize: Theme.captionSize
                    font.weight: row.current ? Font.DemiBold : Font.Normal
                    opacity: row.current ? 1 : 0.8
                    elide: Text.ElideRight
                }

                PopupText {
                    anchors {
                        left: name.right
                        leftMargin: 6
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    text: row.modelData.artist
                    font.pixelSize: Theme.captionSize
                    opacity: 0.45
                    elide: Text.ElideRight
                }
            }

            // The duration gives way to remove on hover without shifting titles.
            Item {
                id: tail

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: root.queueTailWidth
                height: parent.height

                PopupText {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !row.hovered
                    text: Mpd.clock(row.modelData.duration)
                    font.pixelSize: Theme.footnoteSize
                    opacity: 0.4
                }

                PopupButton {
                    anchors.right: parent.right
                    width: root.buttonWidth
                    height: root.rowHeight
                    visible: row.hovered
                    name: "Remove " + (row.modelData.title || "track") + " from queue"
                    glyph: Theme.glyph.queueRemove
                    onTapped: Mpd.removeAt(row.modelData.pos)
                }
            }
        }
    }
}

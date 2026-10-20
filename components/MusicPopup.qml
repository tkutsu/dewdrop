import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs
import qs.components
import qs.services
import "../MediaText.js" as MediaText

// Everything the mpd tooltip's five lines of text were reaching for: the cover,
// a position that can be dragged rather than only read, the transport, the
// player's own volume, and the queue MPD is working through — which can be
// played from, reordered and cut down without opening the player it belongs to.
Popup {
    id: root
    ChoiceBlink { id: choice }

    readonly property int columnWidth: 290
    readonly property int volumeIconWidth: 16
    // The pill's colour for the track, taken off the sleeve (Music.accent),
    // so the position here is the same line as the one round the pill.
    property color accent: Theme.fg
    // Fixed readout space keeps both tracks aligned as the figures change.
    readonly property int readoutWidth: 84
    readonly property int sliderWidth: columnWidth - readoutWidth - 2
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
    // Odd-sized header targets center the 7px plus and close glyphs on pixels.
    readonly property int headerButtonSize: 21
    readonly property int queueTailWidth: 60

    // Whether the quit button in the header has been pressed once. See the
    // button itself for why it takes two.
    property bool quitArmed: false


    // Queue and playlist changes redraw inside a fixed compositor surface.
    reserveHeight: root.vPadding + root.bottomPadding + playerHeader.height
        + queueSeparator.height + root.visibleRows * root.rowHeight + root.spacing * 2
        + (storedPlaylists.visible ? storedPlaylists.height + root.spacing
            + (Mpd.playlistsOpen ? 0 : Mpd.playlists.length * root.rowHeight) : 0)

    property var removalQueue: null
    property int removing: -1
    property real departureFade: 0
    property real departureFold: 0
    readonly property bool removingTrack: removalQueue !== null || removalResize.running

    // As in notifications, fade first, close the slot, then resize the popup.
    function removeTrack(queue, pos): void {
        if (root.removingTrack || Mpd.queue !== queue)
            return;
        if (!root.animateContents) {
            Mpd.removeAt(pos);
            return;
        }
        list.cancelFlick();
        list.heldHeight = list.height;
        list.scrollBeforeRemoval = list.contentY;
        root.removalQueue = queue;
        root.removing = pos;
        removal.start();
    }

    function finishRemoval(): void {
        removal.stop();
        removalResize.restart();
        root.removalQueue = null;
        root.removing = -1;
        root.departureFade = 0;
        root.departureFold = 0;
        list.heldHeight = -1;
    }

    SequentialAnimation {
        id: removal
        NumberAnimation { target: root; property: "departureFade"; from: 0; to: 1; duration: Theme.fadeMs }
        NumberAnimation {
            target: root
            property: "departureFold"
            from: 0
            to: 1
            duration: Theme.fadeMs
            easing.type: Easing.OutCubic
        }
        ScriptAction { script: Mpd.removeAt(root.removing) }
        // Keep the closed slot until MPD replies; restore it if no reply arrives.
        PauseAnimation { duration: 1000 }
        ScriptAction { script: root.finishRemoval() }
    }

    Timer {
        id: removalResize
        interval: Theme.fadeMs
    }

    Row {
        id: playerHeader
        spacing: 10

        Item {
            width: root.artSize
            height: root.artSize

            ClippingRectangle {
                id: artFrame
                anchors.fill: parent
                radius: root.radius - root.padding
                color: "transparent"

                Image {
                    id: cover
                    visible: status === Image.Ready
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    source: Mpd.cover
                    sourceSize.width: 192
                    sourceSize.height: 192
                }

                Rectangle {
                    anchors.fill: parent
                    visible: cover.status === Image.Ready
                    color: Qt.rgba(0, 0, 0, 0.12)
                }

                Rectangle {
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                    }
                    height: root.transportBand
                    visible: cover.status === Image.Ready

                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: Theme.scrim
                        }
                        GradientStop {
                            position: 1
                            color: "transparent"
                        }
                    }
                }

                Item {
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: 4
                    }
                    height: root.buttonWidth

                    Repeater {
                        model: [
                            {
                                name: "Random playback: " + (Mpd.randomOn ? "on" : "off"),
                                glyph: Mpd.randomOn ? Theme.glyph.randomOn : Theme.glyph.randomOff,
                                act: () => Mpd.toggleRandom()
                            },
                            {
                                name: "Repeat mode: " + Mpd.repeatMode,
                                glyph: Mpd.repeatIcon,
                                act: () => Mpd.cycleRepeat()
                            }
                        ]

                        delegate: Item {
                            required property var modelData
                            required property int index

                            x: index * (parent.width - width)
                            width: root.buttonWidth
                            height: root.buttonWidth

                            Glyph {
                                anchors.centerIn: parent
                                text: parent.modelData.glyph
                                fontSize: Theme.glyphSizeLarge
                                implicitHeight: parent.height
                                color: "white"
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    shadowEnabled: true
                                    shadowColor: "black"
                                    shadowOpacity: 0.85
                                    shadowBlur: 0.5
                                    blurMax: 4
                                    shadowVerticalOffset: 1
                                }
                            }

                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.name
                            Accessible.onPressAction: if (enabled && visible)
                                modelData.act()
                            readonly property var keyPress: modelData.act

                            TapHandler {
                                onTapped: parent.modelData.act()
                            }
                        }
                    }
                }

                // The transport, on the cover rather than under the column beside
                // it. The three of them were a row of their own at the bottom of
                // the popup, which is a row of its own worth of height for the
                // three controls least in need of the room — and the picture is
                // already the thing the pointer goes to.
                //
                // A band shading into the foot of the artwork, because the glyphs
                // are white and the artwork underneath them is whatever it is.
                Item {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: root.transportBand

                    Rectangle {
                        anchors.fill: parent
                        visible: cover.status === Image.Ready

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
                    }

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4

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

                            delegate: Item {
                                required property var modelData
                                required property int index

                                x: index * (parent.width - width) / 2
                                width: root.buttonWidth
                                height: root.transportBand

                                Glyph {
                                    anchors.centerIn: parent
                                    text: parent.modelData.glyph
                                    fontSize: Theme.glyphSizeLarge + (parent.index === 1 ? 4 : 0)
                                    implicitHeight: parent.height
                                    color: "white"
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        shadowEnabled: true
                                        shadowColor: "black"
                                        shadowOpacity: 0.85
                                        shadowBlur: 0.5
                                        blurMax: 4
                                        shadowVerticalOffset: 1
                                    }
                                }

                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.name
                                Accessible.onPressAction: if (enabled && visible)
                                    modelData.act()
                                readonly property var keyPress: modelData.act

                                TapHandler {
                                    onTapped: parent.modelData.act()
                                }
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
                height: Math.max(songTitle.implicitHeight, quit.implicitHeight)

                Marquee {
                    id: songTitle

                    anchors {
                        left: parent.left
                        right: add.left
                        rightMargin: 6
                        verticalCenter: parent.verticalCenter
                    }
                    text: MediaText.display(Mpd.title)
                    contentWidth: songTitleText.implicitWidth
                    implicitHeight: songTitleText.implicitHeight
                    hovered: titleHover.hovered

                    HoverHandler { id: titleHover; parent: songTitle }

                    PopupText {
                        id: songTitleText
                        text: songTitle.text
                        font.weight: Font.DemiBold
                        elide: Text.ElideNone
                    }
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
                    implicitHeight: root.headerButtonSize
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
                    implicitHeight: root.headerButtonSize
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
                rightPadding: Theme.popupInset
                text: [Mpd.artist, Mpd.album].filter(part => part).map(MediaText.display).join("  ·  ")
                color: Theme.label2
                elide: Text.ElideRight
            }

            // MPD volume is independent of the system output level.
            VolumeRow {
                visible: Mpd.volume >= 0
                name: "Music"
                iconBeforeReadout: true
                leftPadding: 0
                rightPadding: Theme.popupInset
                spacing: 2
                icon: Mpd.volumeIcon
                volume: Math.max(0, Mpd.volume)
                iconWidth: root.volumeIconWidth
                iconFontSize: Theme.popupGlyphSize
                sliderWidth: root.sliderWidth
                readoutWidth: root.readoutWidth - Theme.popupInset
                readoutColor: Theme.label2
                readoutFontSize: Theme.captionSize
                wheelStep: 0.05
                wheelSnap: true
                onMoved: value => Mpd.setVolume(value)
                onIconTapped: Mpd.toggleMute()
            }

            Item {
                width: 1
                height: 3
            }

            // How far through, twice over: the track says how far, the figures
            // say how far in what. They were a row apart from each other and
            // are one reading.
            Row {
                height: Theme.popupTextSize + 4
                spacing: 2

                Slider {
                    id: playback
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.sliderWidth
                    name: "Playback position"
                    value: Mpd.duration > 0 ? Mpd.elapsed / Mpd.duration : 0
                    // A stream has no length to seek through.
                    enabled: Mpd.duration > 0
                    knob: false
                    fill: root.accent
                    wave: waveform.samples.length > 0
                    waveSamples: waveform.samples
                    wavePulse: waveform.pulse
                    MusicWaveform {
                        id: waveform
                        active: root.visible
                        playing: root.visible && Mpd.state === "play" && !Theme.reduceMotion
                    }
                    // Ten seconds a notch, as on the pill.
                    wheelStep: Mpd.duration > 0 ? 10 / Mpd.duration : 0
                    onMoved: value => Mpd.seekTo(value)
                }

                PopupText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.readoutWidth
                    rightPadding: Theme.popupInset
                    horizontalAlignment: Text.AlignRight
                    text: Mpd.duration > 0 ? `${Mpd.clock(Mpd.elapsed)} / ${Mpd.clock(Mpd.duration)}` : Mpd.clock(Mpd.elapsed)
                    color: Theme.label2
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
        id: storedPlaylists
        width: root.bodyWidth
        spacing: 0
        // Nothing saved, nothing to say.
        visible: Mpd.playlists.length > 0

        PopupSeparator {
            width: root.bodyWidth
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
                color: Theme.label2
            }

            PopupText {
                id: headLabel

                anchors.left: fold.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "Playlists"
                color: Theme.label2
                font.pixelSize: Theme.captionSize
                font.weight: Font.DemiBold
            }

            PopupText {
                anchors.left: headLabel.right
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: String(Mpd.playlists.length)
                color: Theme.label3
                font.pixelSize: Theme.footnoteSize
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
                blink: choice

                width: root.bodyWidth
                height: root.rowHeight

                readonly property bool armed: Mpd.armedPlaylist === entry.modelData

                // Leaving the row is how a half-pressed delete is called off.
                // There is no cancel button because there does not need to be
                // one: the way out is the direction the pointer was going.
                onHoveredChanged: if (!entry.hovered && entry.armed && !entry.chosen)
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
                    anchors.rightMargin: Theme.popupInset
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
                                // tick the launcher's power rows put up before
                                // they turn the machine off.
                                name: (entry.armed ? "Confirm delete " : "Delete ") + entry.modelData,
                                glyph: entry.armed ? Theme.glyph.powerConfirm : Theme.glyph.playlistRemove,
                                live: true,
                                warn: entry.armed,
                                act: () => {
                                    if (entry.armed) {
                                        const name = entry.modelData;
                                        choice.start(entry, () => Mpd.removePlaylist(name));
                                    } else if (!choice.running)
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
                            live: modelData.live && !choice.running
                            warn: modelData.warn
                            onTapped: modelData.act()
                        }
                    }
                }
            }
        }
    }

    PopupSeparator {
        id: queueSeparator
        width: root.bodyWidth
        visible: list.count > 0
    }

    ListView {
        id: list

        // In the accessibility tree as a list to scroll, half a view a step.

        Accessible.role: Accessible.List

        Accessible.name: "Queue"

        Accessible.onScrollUpAction: contentY = Math.max(originY, contentY - height / 2)

        Accessible.onScrollDownAction: contentY = Math.min(originY + Math.max(0, contentHeight - height), contentY + height / 2)

        width: root.bodyWidth
        // A short queue draws short rather than padding itself out with empty
        // rows, the same way the launcher's list does.
        property real heldHeight: -1
        height: heldHeight >= 0 ? heldHeight : Math.min(count, root.visibleRows) * root.rowHeight
        Behavior on height {
            enabled: root.animateContents && removalResize.running
            NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.OutCubic }
        }
        clip: true
        layer.enabled: contentHeight > height
        layer.effect: ScrollEdges {
            view: list
        }
        model: root.removalQueue ?? (reorder.showing ? reorder.rows : Mpd.queue)
        enabled: !root.removingTrack
        interactive: !reorder.showing && !root.removingTrack
        // Ease wheel motion while keeping the ends firm.
        boundsBehavior: Flickable.StopAtBounds
        SmoothScroll { view: list }

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

        property real scrollBeforeRefresh: NaN
        property real scrollBeforeRemoval: 0
        property bool revealCurrentPending: false

        // Measure refreshed rows before restoring browsing or following a track change.
        function updateQueuePosition() {
            if (!isNaN(scrollBeforeRefresh)) {
                list.forceLayout();
                list.contentY = Math.max(0, Math.min(list.contentHeight - list.height, scrollBeforeRefresh));
                scrollBeforeRefresh = NaN;
            }
            if (revealCurrentPending) {
                revealCurrentPending = false;
                if (Mpd.songPos >= 0 && Mpd.songPos < list.count) {
                    list.forceLayout();
                    list.positionViewAtIndex(Mpd.songPos, ListView.Contain);
                }
            }
        }

        Connections {
            target: Mpd

            function onQueueChanged() {
                if (root.removalQueue !== null && root.removalQueue !== Mpd.queue)
                    root.finishRemoval();
            }

            function onSongPosChanged() {
                list.revealCurrentPending = true;
                Qt.callLater(list.updateQueuePosition);
            }

            // The model is a plain array and is replaced whole on every
            // refresh, which puts the view back at the top with it. Removing a
            // song should not cost you your place in the queue it came out of.
            function onQueueChanging() {
                list.scrollBeforeRefresh = root.removalQueue !== null ? list.scrollBeforeRemoval : list.contentY;
                Qt.callLater(list.updateQueuePosition);
            }

        }

        ListReorder {
            id: reorder
            view: list
            model: Mpd.queue
            rowHeight: root.rowHeight
            rightGuard: root.buttonWidth + Theme.popupInset
            onMoved: (from, to) => { if (from !== to) Mpd.moveTo(rows[from].pos, rows[to].pos); }
            onClicked: index => { if (!choice.running) Mpd.playAt(rows[index].pos); }
            lifted: Component {
                QueueTrack {
                    song: reorder.showing ? reorder.rows[reorder.from] : null
                    number: reorder.to + 1
                    current: reorder.from === Mpd.songPos
                    tailWidth: root.queueTailWidth
                }
            }
        }

        delegate: PopupRow {
            id: row

            required property var modelData
            required property int index
            blink: choice
            acceptsTap: false

            readonly property bool current: Mpd.songPos === row.index

            name: "Play " + (row.modelData.title || "Track " + (row.index + 1))
            width: ListView.view.width
            height: root.rowHeight * (row.index === root.removing ? 1 - root.departureFold : 1)
            onTapped: if (!choice.running) Mpd.playAt(row.modelData.pos)
            opacity: reorder.showing && row.index === reorder.from ? 0
                : row.index === root.removing ? 1 - root.departureFade : 1
            transform: Translate {
                y: reorder.shift(row.index)

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
            QueueTrack {
                anchors.fill: parent
                song: row.modelData
                number: row.index + 1
                current: row.current
                tailWidth: root.queueTailWidth
                showDuration: !row.hovered
            }

            // The duration gives way to remove on hover without shifting titles.
            Item {
                id: tail

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: root.queueTailWidth
                height: parent.height

                PopupButton {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.popupInset
                    width: root.buttonWidth
                    height: root.rowHeight
                    visible: row.hovered
                    name: "Remove " + (row.modelData.title || "track") + " from queue"
                    glyph: Theme.glyph.queueRemove
                    live: !choice.running && !root.removingTrack
                    onTapped: {
                        const queue = Mpd.queue;
                        const pos = row.modelData.pos;
                        choice.start(row, () => {
                            root.removeTrack(queue, pos);
                        });
                    }
                }
            }
        }
    }
}

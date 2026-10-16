import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs
import qs.components
import qs.services

// Whatever else is playing — a browser tab, a video, a podcast app, anything
// that speaks MPRIS — in a pill of its own beyond the music pill. mpd
// publishes no MPRIS (services/Mpd.qml), so nothing shows here twice.
//
// The title and play/pause, and no popup: the app itself is where the rest
// of it lives, and the title takes you there. Right click plays or pauses
// too, and the wheel seeks, as on the music pill.
BarItem {
    id: root
    name: "Now Playing"

    // The player to show: the one playing, or failing that, the one that
    // played last, while it is still paused on something. Pausing one tab
    // should not put up another that was paused long before.
    readonly property var live: Mpris.players.values.filter(p => p.trackTitle !== "" && p.playbackState !== MprisPlaybackState.Stopped)
    readonly property MprisPlayer playingNow: live.find(p => p.isPlaying) ?? null
    property MprisPlayer playedLast: null
    onPlayingNowChanged: if (playingNow)
        playedLast = playingNow
    readonly property MprisPlayer player: playingNow ?? (live.includes(playedLast) ? playedLast : live[0] ?? null)

    // Comes out of its neighbour and is drawn back into it; the bar draws the
    // pill off `reveal` (Bar.drop), and nothing folds.
    stowed: player === null
    folds: false

    readonly property bool settled: reveal >= 1
    readonly property bool playing: player?.isPlaying ?? false

    // The title and the line, kept while the pill goes: the player is gone
    // before the pill is, and neither should blank on the way.
    property string shownLabel: ""
    property real progress: -1
    readonly property string label: player?.trackTitle ?? ""
    readonly property bool timed: (player?.positionSupported && player.lengthSupported && player.length > 0) ?? false
    onLabelChanged: if (label)
        shownLabel = label
    Component.onCompleted: if (label)
        shownLabel = label

    // MPRIS sends no word as the position runs, only when it jumps, so it is
    // asked once a second while playing; the pill carries the line on in
    // between (Pill.rate).
    function track() {
        if (root.player)
            root.progress = root.timed ? root.player.position / root.player.length : -1;
    }
    readonly property real rate: root.playing && root.timed ? (root.player.rate || 1) / root.player.length : 0

    onPlayerChanged: track()
    onTimedChanged: track()

    Timer {
        interval: 1000
        repeat: true
        running: root.playing
        onTriggered: root.player.positionChanged()
    }

    Connections {
        target: root.player
        function onPositionChanged() {
            root.track();
        }
    }

    function toggle() {
        if (root.player?.canTogglePlaying)
            root.player.togglePlaying();
    }

    // The player's own window, the way a notification's sender is found.
    function show() {
        if (root.player)
            Notifications.focusSender({
                desktopEntry: root.player.desktopEntry,
                appName: root.player.identity
            });
    }

    spacing: 0
    // Each target presses in by itself (PressGlass), as on the music pill.
    dips: false
    actions: ({
            [Qt.RightButton]: () => root.toggle()
        })

    // The title's room, which is what sizes the pill, springing to a new
    // title's width as the music pill's does.
    Item {
        id: titleRoom
        readonly property bool inkLit: true

        Layout.fillHeight: true
        implicitWidth: title.implicitWidth
        scale: titlePress.scale

        PressGlass {
            id: titlePress
            icon: titleRoom
            area: titleTap
        }

        Accessible.role: Accessible.Button
        Accessible.name: "Show " + (root.player?.identity ?? "player")
        Accessible.onPressAction: if (enabled && visible)
            root.show()

        TapHandler {
            id: titleTap
            // Keep the top screen pixel inside the target as it shrinks.
            margin: Theme.barInset
            onTapped: root.show()
        }

        Behavior on implicitWidth {
            enabled: root.settled
            NumberAnimation {
                duration: Theme.reduceMotion ? Theme.turnMs : 640
                easing.type: Theme.reduceMotion ? Easing.OutCubic : Easing.BezierSpline
                easing.bezierCurve: Theme.mediaTitleCurve
            }
        }

        Marquee {
            id: title

            width: Math.min(implicitWidth, titleRoom.width)
            height: parent.height
            text: root.shownLabel
            maxWidth: Theme.mediaTitleWidth
            contentWidth: titleText.implicitWidth
            active: Settings.scrollMusicTitles && !Theme.reduceMotion && root.settled

            BarText {
                id: titleText
                height: parent.height
                text: root.shownLabel
                maxWidth: Settings.scrollMusicTitles && !Theme.reduceMotion ? 0 : Theme.mediaTitleWidth
            }
        }
    }

    // Play/pause to the right of the title, with its gap before it.
    Item {
        id: slot
        readonly property bool inkLit: true

        Layout.fillHeight: true
        implicitWidth: play.implicitWidth + Theme.mediaGap
        scale: playPress.scale

        PressGlass {
            id: playPress
            icon: slot
            area: playTap
        }

        Accessible.role: Accessible.Button
        Accessible.name: root.playing ? "Pause" : "Play"
        Accessible.onPressAction: if (enabled && visible)
            root.toggle()

        TapHandler {
            id: playTap
            margin: Theme.pressDip
            onTapped: root.toggle()
        }

        // What pressing it will do, as on the music pill.
        Glyph {
            id: play

            x: Theme.mediaGap
            height: parent.height
            text: root.playing ? Theme.glyph.paused : Theme.glyph.playing
        }
    }

    scrolls: root.player?.canSeek ?? false
    Accessible.onScrollUpAction: scrollUp()
    Accessible.onScrollDownAction: scrollDown()
    onScrollUp: root.player?.seek(-10)
    onScrollDown: root.player?.seek(10)
}

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
// The app icon, track title and play/pause, and no popup: the app
// itself is where the rest of it lives, and the title takes you there.
// Right click plays or pauses too, and the wheel seeks, as on the music pill.
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
    stowed: !Settings.showMpris || player === null || (paused && !expanded)
    folds: false

    // Keep the icon on the gathering glass; the title slides behind its edge.
    readonly property bool sliding: pill?.slidesContent ?? false
    readonly property real glassWidth: sliding ? pill.foldBox.z : width
    readonly property real glassLeft: sliding ? pill.foldBox.x : 0
    readonly property real iconInset: Math.min(padLeft, Math.max(0, (glassWidth - appIcon.width) / 2))
    readonly property real titleLoss: sliding ? Math.max(0, pill.width - glassWidth) : 0
    // Hand off only once the entire icon has crossed the neighbour's edge.
    readonly property bool iconInCentre: reveal <= 0 || (sliding
        ? glassLeft + iconInset >= pill.width + Theme.pillSpread
        : reveal <= 0.3)
    readonly property bool settled: reveal >= 1
    readonly property bool playing: player?.isPlaying ?? false
    readonly property bool paused: Settings.showMpris && player?.playbackState === MprisPlaybackState.Paused
    property bool expanded: false
    onPausedChanged: expanded = false

    // Reveal the controls and ask the selected app to resume playback.
    function expand() {
        if (!root.paused)
            return;
        root.expanded = true;
        if (root.player.canPlay)
            root.player.play();
    }

    // The title and the line, kept while the pill goes: the player is gone
    // before the pill is, and neither should blank on the way.
    property string shownLabel: ""
    property string shownApp: ""
    property real progress: -1
    readonly property string appName: player?.identity || player?.desktopEntry || ""
    readonly property string appId: player?.desktopEntry || player?.identity || ""
    readonly property string label: player?.trackTitle ?? ""
    readonly property bool timed: (player?.positionSupported && player.lengthSupported && player.length > 0) ?? false
    onLabelChanged: if (label)
        shownLabel = label
    onAppIdChanged: if (appId)
        shownApp = appId
    Component.onCompleted: {
        if (label)
            shownLabel = label;
        if (appId)
            shownApp = appId;
    }

    // MPRIS sends no word as the position runs, only when it jumps, so it is
    // asked once a second while playing; the pill carries the line on in
    // between (Pill.rate).
    function track() {
        if (!root.player || !root.timed)
            return;
        if (root.progress >= 0 || !timingSettle.running)
            root.progress = root.player.position / root.player.length;
    }
    readonly property real rate: root.playing && root.timed ? (root.player.rate || 1) / root.player.length : 0

    onPlayerChanged: {
        expanded = false;
        if (player) {
            progress = -1;
            timingSettle.restart();
        } else {
            timingSettle.stop();
        }
    }
    onTimedChanged: {
        timingSettle.restart();
        track();
    }

    // Only show new timing once it settles. Once shown, hold the last known
    // progress through seek metadata gaps until the track or player changes.
    Timer {
        id: timingSettle
        interval: 500
        onTriggered: root.track()
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.playing
        onTriggered: root.player.positionChanged()
    }

    Connections {
        target: root.player
        function onTrackChanged() {
            root.progress = -1;
            timingSettle.restart();
        }
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
        implicitWidth: appIcon.implicitWidth + Theme.mediaGap + title.implicitWidth
        scale: titlePress.scale
        transform: Translate { x: root.glassLeft + root.iconInset - root.padLeft }

        PressGlass {
            id: titlePress
            icon: titleRoom
            area: titleTap
            textPress: true
        }

        Accessible.role: Accessible.Button
        Accessible.name: "Show " + (root.appName || "player")
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

        AppIcon {
            id: appIcon
            scale: root.sliding ? root.pill.iconScale : 1
            windowClass: root.shownApp
            visible: !root.sliding || !root.iconInCentre
            height: parent.height
        }

        Marquee {
            id: title

            x: appIcon.width + Theme.mediaGap
            width: Math.max(0, Math.min(implicitWidth, titleRoom.width - x - root.titleLoss))
            height: parent.height
            text: root.shownLabel
            maxWidth: Theme.mediaTitleWidth
            contentWidth: titleText.implicitWidth
            active: Settings.scrollMusicTitles && !Theme.reduceMotion
            paused: !root.settled
            // Reuse the marquee edge shader as the contracting edge overtakes text.
            travel: root.titleLoss

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
        opacity: root.sliding ? pill.geometry.contents(root.reveal) : 1
        transform: Translate { x: root.glassLeft + root.glassWidth - (root.pill?.width ?? root.width) }

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
            // Keep the top screen pixel inside the target as it shrinks.
            margin: Theme.barInset
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

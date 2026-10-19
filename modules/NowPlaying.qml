import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs
import qs.components
import qs.services

// Whatever else is playing — a browser tab, a video, a podcast app, anything
// that speaks MPRIS — in a pill of its own beyond the music pill. mpd
// publishes no MPRIS (services/Mpd.qml), so nothing shows here twice.
//
// The title and app icon focus the player; its playback control appears on hover.
// Right click plays or pauses, and the wheel seeks, as on the music pill.
BarItem {
    id: root
    name: appName || "player"

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
    // Move and crossfade into the central icon as the glass joins its neighbour.
    property Item mergedIcon: null
    readonly property MediaIconHandoff iconHandoff: MediaIconHandoff {
        source: appIcon
        target: root.mergedIcon
        reveal: root.reveal
        restingX: root.sliding ? root.glassLeft + root.iconInset - root.padLeft : 0
    }
    readonly property bool iconInCentre: iconHandoff.progress > 0
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

    // Quit only players that explicitly support closing through MPRIS.
    function closePlayer() {
        if (root.player?.canQuit)
            root.player.quit();
    }

    // Let the player select its media window; otherwise match its app and title.
    function focusPlayer() {
        if (!root.player)
            return;
        if (root.player.canRaise) {
            root.player.raise();
            return;
        }
        const entry = DesktopEntries.byId(root.player.desktopEntry);
        const names = [root.player.desktopEntry, entry?.startupClass, root.player.identity]
            .filter(s => s).map(s => s.toLowerCase());
        const windows = Hyprland.toplevels.values.filter(t => names.includes((t.wayland?.appId || t.lastIpcObject?.class || "").toLowerCase()));
        const mediaWindows = windows.filter(t => (t.title || "").toLowerCase().includes(root.label.toLowerCase()));
        const recent = (mediaWindows.length ? mediaWindows : windows)
            .sort((a, b) => (a.lastIpcObject?.focusHistoryID ?? 1e9) - (b.lastIpcObject?.focusHistoryID ?? 1e9))[0];
        if (recent)
            Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${recent.address}" })`);
    }

    spacing: 0
    dips: false
    actions: ({
            [Qt.LeftButton]: () => root.focusPlayer(),
            [Qt.RightButton]: () => root.toggle()
        })

    property real controlReveal: containsMouse ? 1 : 0
    contentAnimating: previousStep.animating || nextStep.animating
    Behavior on controlReveal {
        NumberAnimation { duration: Theme.fadeMs; easing.type: Easing.InOutQuad }
    }

    // The title's room, which is what sizes the pill, springing to a new
    // title's width as the music pill's does.
    Item {
        id: titleRoom
        readonly property bool inkLit: true

        Layout.fillHeight: true
        implicitWidth: leading.width + nextStep.width + Math.max(title.implicitWidth, play.implicitWidth)
        transform: Translate { x: root.iconHandoff.sourceX }

        // Keep press feedback off the app icon while it follows the closing glass.
        PressGlass {
            id: titlePress
            icon: titleRoom
            area: root
            down: root.acting || playTap.acting
            textPress: true
        }

        Behavior on implicitWidth {
            enabled: root.settled
            NumberAnimation {
                duration: Theme.reduceMotion ? Theme.turnMs : 640
                easing.type: Theme.reduceMotion ? Easing.OutCubic : Easing.BezierSpline
                easing.bezierCurve: Theme.mediaTitleCurve
            }
        }

        // Match Music's hover controls: previous replaces the app icon,
        // and next unfolds into the space before the title.
        Item {
            id: leading
            width: Math.max(appIcon.implicitWidth + Theme.mediaGap, previousStep.implicitWidth)
            height: parent.height

            MediaStep {
                id: previousStep
                width: implicitWidth
                height: parent.height
                previous: true
                open: root.containsMouse && root.settled && (root.player?.canGoPrevious ?? false)
                settled: root.settled
                onTriggered: if (root.player?.canGoPrevious)
                    root.player.previous()
            }

            AppIcon {
                id: appIcon
                scale: 1
                tightWidth: true
                opacity: root.settled ? 1 - previousStep.opacity : 1 - root.iconHandoff.progress
                windowClass: root.shownApp
                visible: !root.sliding || root.iconHandoff.progress < 1
                height: parent.height
            }
        }

        MediaStep {
            id: nextStep
            x: leading.width
            width: implicitWidth
            height: parent.height
            open: root.containsMouse && root.settled && (root.player?.canGoNext ?? false)
            settled: root.settled
            onTriggered: if (root.player?.canGoNext)
                root.player.next()
        }

        Marquee {
            id: title

            x: leading.width + nextStep.width
            width: Math.max(0, Math.min(implicitWidth, titleRoom.width - x - root.titleLoss
                - root.controlReveal * (play.implicitWidth + Theme.mediaGap)))
            height: parent.height
            text: root.shownLabel
            maxWidth: Theme.mediaTitleWidth
            contentWidth: titleText.implicitWidth
            scale: titlePress.scale
            hovered: root.containsMouse
            paused: root.contentAnimating || !root.settled
            // Reuse the marquee edge shader as the contracting edge overtakes text.
            travel: root.titleLoss

            BarText {
                id: titleText
                height: parent.height
                text: root.shownLabel
            }
        }

        // Overlay the control without adding room to the pill's layout.
        Glyph {
            id: play

            x: titleRoom.width - width - root.titleLoss
            height: parent.height
            scale: titlePress.scale
            opacity: root.controlReveal * (root.sliding ? root.pill.geometry.contents(root.reveal) : 1)
            text: root.playing ? Theme.glyph.paused : Theme.glyph.playing

            ClickArea {
                id: playTap
                anchors.fill: parent
                enabled: root.player?.canTogglePlaying ?? false
                acceptedButtons: Qt.LeftButton
                name: (root.playing ? "Pause " : "Play ") + (root.appName || "player")
                actions: ({ [Qt.LeftButton]: () => root.toggle() })
            }
        }
    }

    scrolls: root.player?.canSeek ?? false
    Accessible.onScrollUpAction: scrollUp()
    Accessible.onScrollDownAction: scrollDown()
    onScrollUp: root.player?.seek(-10)
    onScrollDown: root.player?.seek(10)
}

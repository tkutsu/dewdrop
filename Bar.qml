import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.components
import qs.modules

PanelWindow {
    id: bar

    required property var modelData
    screen: modelData

    // wrules.lua blurs layers by namespace; this needs a matching rule there
    // for the bar to get blurred. The rule ignores anything under 0.3 alpha,
    // which is what keeps the blur to the pills instead of spreading it across
    // the transparent strip they float on.
    WlrLayershell.namespace: "quickshell:bar"
    WlrLayershell.layer: WlrLayer.Top

    anchors {
        top: true
        left: true
        right: true
    }
    // Down to the bottom edge of the pills and no further. The air under them
    // is Hyprland's own window gap (general:gaps_out), the same gap that puts a
    // tiled window's left edge level with the left pill; reserving a margin
    // here as well would stack on top of it and read as double.
    //
    // Except once the gaps are off, when there is no window gap left to double:
    // the strip would meet the window flush along a line the pills sit hard
    // against, with their margin still above them. Claiming that margin a
    // second time puts the same air back underneath, and the pills — anchored
    // from the top, so they do not move — end up centred in the strip instead
    // of resting on its bottom edge.
    //
    // Off `gapless` rather than `mergeProgress`, which is the animated form of
    // the same thing: this is the layer surface's exclusive zone, and every
    // value it passes through is a relayout of the windows below. It changes
    // once, while the strip it belongs to fades in over it.
    implicitHeight: Theme.barHeight + Theme.barMargin + (bar.gapless ? Theme.barMargin : 0)
    color: "transparent"

    // Whether Hyprland has taken the gaps off the workspace this bar's monitor
    // is showing. It does that for a lone tiled window and for a fullscreen one
    // — the w[tv1] and f[1] workspace rules in hypr/configs/tags.lua — and the
    // bar follows, so a desktop with nothing to separate gets a bar with
    // nothing to separate either.
    //
    // Re-derived rather than read: Hyprland will tell you the rules it holds
    // (`hyprctl workspacerules`) but not which one matched a workspace, so this
    // is a copy of that condition and has to be kept in step with tags.lua by
    // hand. Per monitor, not per session — one screen can be down to its last
    // window while the other is not.
    readonly property var hlMonitor: Hyprland.monitors.values.find(m => m.name === bar.modelData.name) ?? null

    readonly property bool gapless: {
        const id = bar.hlMonitor?.activeWorkspace?.id;
        if (id === undefined)
            return false;

        let tiled = 0;
        for (const toplevel of Hyprland.toplevels.values) {
            if (toplevel.workspace?.id !== id)
                continue;

            const client = toplevel.lastIpcObject;
            if (client?.fullscreen)
                return true;
            // Whether a window floats is only known from the last `hyprctl
            // clients` refresh, and one that opened since has no object to ask.
            // Counting those as tiled is what closes the gaps' return to the
            // moment a second window opens rather than a refresh later.
            if (client && (client.floating || client.hidden))
                continue;
            tiled++;
        }
        return tiled === 1;
    }

    // 0 while the pills are three islands, 1 while the bar is one strip. Both
    // halves of the change are derived from this rather than animating apart,
    // which is what keeps the fill and the pills over it in step frame by
    // frame — they are drawing the same colour twice and have to agree on how
    // much of it each is carrying.
    property real mergeProgress: bar.gapless ? 1 : 0

    Behavior on mergeProgress {
        NumberAnimation {
            duration: Theme.fadeMs
            easing.type: Easing.InOutQuad
        }
    }

    // The air the pills float in, in the pills' own colour: three islands on a
    // transparent strip become one line, without any of them moving. Square and
    // borderless on purpose — the rounded ends and the outline are what make a
    // pill a pill, and this is the strip they stop being.
    //
    // Declared before them so it goes behind, but they hand their fill over as
    // it comes up rather than stacking on it (see Pill.mergeProgress).
    Rectangle {
        anchors.fill: parent
        visible: bar.mergeProgress > 0
        color: Theme.barBg

        // Two translucent blacks over one another do not add up to one of them:
        // fading both ends at once the obvious way leaves the pills lighter
        // than the strip between them for the length of the fade. This is the
        // alpha that, under a pill carrying the rest of it, composites back to
        // exactly barBg — 0 at the start, 1 at the end, and the pill's own
        // colour everywhere in between.
        //
        // The blur is the one thing that cannot be faded with it: the gaps have
        // to cross wrules.lua's 0.3 alpha on the way to 0.5, so the compositor
        // picks them up partway through rather than gradually.
        opacity: {
            const a = Theme.barBg.a;
            return (1 - (1 - a) / (1 - a * (1 - bar.mergeProgress))) / a;
        }
    }

    // Anywhere on the bar, pills or the air between them. The drawer stays
    // open while the pointer is here or down in one of the bar's popups.
    HoverHandler {
        id: barHover
    }

    // "fixed-center": true — the centre pill is centred on the bar, not on
    // whatever space the left and right pills happen to leave behind. Three
    // separately anchored islands do that; a single RowLayout would not. Each
    // one places itself from its `side`, which is the same thing that tells it
    // whether it backs onto a screen edge and owes the margin a hit area.
    Pill {
        id: leftPill

        side: Pill.Side.Left
        mergeProgress: bar.mergeProgress

        Workspaces {}
    }

    // The clock's own separating dot is what sits on the centre line, not the
    // pill around it: the date either side of the dot changes width through the
    // week and the month, and centring the pill would have all of it shuffling
    // sideways under a fixed bar.
    // The glass of the clock and of everything that comes and goes beside it,
    // as one surface (see `drop` below). Declared before those pills so it
    // goes under their contents. Fades with the pills' own slabs once the bar
    // is one strip.
    Liquid {
        anchors.fill: parent
        opacity: 1 - bar.mergeProgress
        visible: opacity > 0

        box0: Qt.vector4d(clockPill.x, Theme.barMargin, clockPill.width, Theme.barHeight)
        box1: bar.noticeDrop
        box2: bar.countdownDrop
        box3: bar.musicDrop
    }

    Pill {
        id: clockPill

        drawsSlab: false
        side: Pill.Side.Centre
        mergeProgress: bar.mergeProgress
        centreOn: clock.centreItem

        Clock {
            id: clock
        }
    }

    // Everything that comes and goes sits either side of the clock, placed off
    // where the clock pill actually ended up rather than given a Side of its
    // own: the centre pill is not where the centre is — it shifts itself so
    // that the clock's dot lands on the middle of the bar rather than the
    // pill's own middle (see Pill.centreOn) — and the only honest way to sit
    // beside something that has moved is to read where it ended up. A spread
    // between each pair of neighbours, the same air all the way along.

    // The pills that come and go beside the clock are drawn into their
    // neighbour the way a drop is — the clock is the one island that is always
    // there, and a thing that is not being shown is taken back into it rather
    // than blinked off. The glass for all of them is one surface (Liquid, under
    // the clock), and each pill's share of it is a box worked out by `drop`
    // from the module's own `reveal`, the same eased 0..1 the drawer folds on.
    //
    // Going away, a pill first lets its contents go, then pulls its far end in
    // until it is round, then travels into the neighbour on its inner side and
    // shrinks inside it; the neck between the two is the glass itself, joining
    // as they come within a spread of each other. Arriving is the same run
    // backwards. `edge` is the neighbour's facing edge, `dir` which way the
    // pill lies from it (1 right, -1 left), `width` the pill at rest.
    function drop(edge, dir, width, reveal) {
        if (reveal <= 0)
            return Qt.vector4d(0, 0, 0, 0);
        const t = 1 - reveal;
        const height = Theme.barHeight;
        const round = bar.ease((t - bar.settle) / 0.45);
        const travel = bar.ease((t - 0.5) / 0.5);
        const shrink = 1 - 0.3 * travel;
        const w = Math.max(height, width - (width - height) * round) * shrink;
        const h = height * shrink;
        const inner = edge + dir * (Theme.pillSpread - (Theme.pillSpread + height * 0.8) * travel);
        return Qt.vector4d(dir > 0 ? inner : inner - w, Theme.barMargin + (height - h) / 2, w, h);
    }

    // How much of a pill's contents show at a given `reveal`, and its outline
    // with them. The first `settle` of leaving is theirs alone: they are gone
    // before the glass under them moves, and arriving, they come in only once
    // it has come to rest. Anything sooner and the outline, drawn round the
    // pill at rest, hung in the air outside glass that was not there yet.
    readonly property real settle: 0.2

    function contents(reveal) {
        return bar.ease((reveal - (1 - bar.settle)) / bar.settle);
    }

    function ease(x) {
        const c = Math.max(0, Math.min(1, x));
        return c * c * (3 - 2 * c);
    }

    readonly property real clockLeft: clockPill.x
    readonly property real clockRight: clockPill.x + clockPill.width

    readonly property vector4d musicDrop: bar.drop(bar.clockLeft, -1, musicPill.width, music.reveal)
    readonly property vector4d countdownDrop: bar.drop(bar.clockRight, 1, countdownPill.width, countdown.reveal)
    // The notice is placed off the timer's glass rather than the clock's, so
    // it goes into the timer while one is set and follows it in as it goes.
    // Once the timer is inside the clock its far edge is too, and the clock's
    // edge is the one to go by.
    readonly property real noticeEdge: countdown.reveal > 0 ? Math.max(bar.clockRight, countdownDrop.x + countdownDrop.z) : bar.clockRight
    readonly property vector4d noticeDrop: bar.drop(bar.noticeEdge, 1, noticePill.width, notice.reveal)

    // The player, alone on the clock's left. What it carries is a song title —
    // text from somewhere else, as long as whoever named the track made it —
    // and nothing else should have to move along every time a new one starts:
    // it is anchored by its right edge, so a longer title only grows it
    // outwards.
    //
    // The pills stay where they rest while their glass runs off from under
    // them; their contents have gone by then (bar.contents).
    Pill {
        id: musicPill

        edges: false
        drawsSlab: false
        contentOpacity: bar.contents(music.reveal)

        side: Pill.Side.Right
        edgeOffset: bar.width - bar.clockLeft + Theme.pillSpread
        mergeProgress: bar.mergeProgress
        // With nothing to play there is no pill, rather than an empty one. Off
        // the module's `reveal` rather than its visibility: hiding an item
        // hides its children with it, so a pill reading its child's `visible`
        // would latch shut the first time mpd was quiet.
        visible: music.reveal > 0
        progress: music.progress
        trackOpacity: contentOpacity

        Music {
            id: music
            foldDuration: Theme.dropMs
            foldEasing: Easing.Linear
        }
    }

    // The timer, immediately right of the clock. It is a clock of another kind
    // and reads as one while the two are neighbours. Anchored by its left edge,
    // so it grows away from the clock. Its label only changes width when its
    // format does — the figures are tabular — so the notice beside it is not
    // shoved along once a second.
    Pill {
        id: countdownPill

        edges: false
        drawsSlab: false
        contentOpacity: bar.contents(countdown.reveal)

        side: Pill.Side.Left
        edgeOffset: bar.clockRight + Theme.pillSpread
        mergeProgress: bar.mergeProgress
        visible: countdown.reveal > 0
        progress: countdown.progress
        trackOpacity: contentOpacity

        Countdown {
            id: countdown
            foldDuration: Theme.dropMs
            foldEasing: Easing.Linear
        }
    }

    // A notification as it comes in, outermost on this side: right of the
    // timer when one is set, of the clock when not. Placed off the timer's
    // glass (bar.noticeEdge), so the two arrive and leave in step. Anchored by
    // its left edge, so it grows away from the clock, and it may run as far as
    // a spread short of the right pill: someone else's text, but read once and
    // then gone, so it gets all the room there is rather than a fixed ceiling.
    Pill {
        id: noticePill

        edges: false
        drawsSlab: false
        contentOpacity: bar.contents(notice.reveal)

        side: Pill.Side.Left
        edgeOffset: bar.noticeEdge + Theme.pillSpread
        mergeProgress: bar.mergeProgress
        // Off the module's `reveal`, never its visibility (see the music pill
        // above).
        visible: notice.reveal > 0

        Notice {
            id: notice
            foldDuration: Theme.dropMs
            foldEasing: Easing.Linear
            room: rightPill.x - Theme.pillSpread - (bar.noticeEdge + Theme.pillSpread)
        }
    }

    Pill {
        id: rightPill

        side: Pill.Side.Right
        mergeProgress: bar.mergeProgress

        // Whatever has nothing to say right now folds away behind this handle,
        // each module in its own place in the row so that opening the drawer
        // puts the pill back exactly as it always was. The modules decide what
        // "nothing to say" is (BarItem.quiet), a middle click can overrule them
        // either way (DrawerPins), and the drawer only decides whether they
        // are showing anyway.
        readonly property var drawable: [audio, email, tasks, updater, bell, satty, idle, wallpaper, night, sys]

        Drawer {
            id: drawer
            holding: rightPill.drawable.some(m => m.here && !m.showsClosed)
            // Or a popup is open: one of the drawer's own modules would fold
            // away from under it.
            pointerNear: barHover.hovered || PopupPointer.hovered > 0 || OpenPopup.owner !== null
        }

        // A pixel less air on its right than the row gives: the speaker's
        // waves thin out to nothing at the edge of its box, and at the full
        // gap the icon beside it read as set apart from it.
        Audio {
            id: audio
            pinKey: "audio"
            stowed: !showsClosed && !drawer.open
            marksPin: drawer.open
            Layout.rightMargin: -1
        }
        Email {
            id: email
            pinKey: "email"
            stowed: !showsClosed && !drawer.open
            marksPin: drawer.open
        }
        Tasks {
            id: tasks
            pinKey: "tasks"
            stowed: !showsClosed && !drawer.open
            marksPin: drawer.open
        }
        Updater {
            id: updater
            pinKey: "updater"
            stowed: !showsClosed && !drawer.open
            marksPin: drawer.open
        }
        NotificationBell {
            id: bell
            pinKey: "bell"
            stowed: !showsClosed && !drawer.open
            marksPin: drawer.open
        }
        Satty {
            id: satty
            pinKey: "satty"
            stowed: !showsClosed && !drawer.open
            marksPin: drawer.open
        }
        IdleInhibit {
            id: idle
            pinKey: "idle"
            stowed: !showsClosed && !drawer.open
            marksPin: drawer.open
        }
        Wallpaper {
            id: wallpaper
            pinKey: "wallpaper"
            stowed: !showsClosed && !drawer.open
            marksPin: drawer.open
        }
        NightMode {
            id: night
            pinKey: "night"
            stowed: !showsClosed && !drawer.open
            marksPin: drawer.open
        }
        Sys {
            id: sys
            pinKey: "sys"
            stowed: !showsClosed && !drawer.open
            marksPin: drawer.open
        }
        // Everything from here on is always shown, so the right end of the
        // pill stays put however much of the drawer is folded away.
        Bluetooth {}
        Network {}
        Tray {
            settingsKey: "tray"
        }
        // Every Glyph on the bar is laid out on its ink, but the language
        // label is text and keeps its advance, which leaves about a pixel
        // of side bearing to the right of the "N". That pixel comes back
        // out, and one more: the launcher's ring meets the N's straight stem
        // only at its middle, and at the measured gap the pair read as
        // further apart than their neighbours. Trimming the gap rather than
        // shifting the label keeps the module's own width fixed, so nothing
        // moves when the layout changes.
        Language {
            settingsKey: "language"
            Layout.rightMargin: -2
        }
        LauncherButton {}
    }

    // A click anywhere on the bar but the right pill puts the drawer away,
    // the way a menu bar's extras fold back once you click on something else.
    // A click in another window is left to the drawer's own timer. A focus
    // grab on the bar would hear it, but Hyprland keeps the pointer on the
    // grabbed surfaces while one is up, and the popups are surfaces of their
    // own: none of them could be hovered with the drawer open, so each one
    // closed as the pointer came down into it.
    //
    // On the bar, this is laid over everything: it looks at each press and
    // turns it down, which hands it on
    // to the module underneath as if this were not here. Not a TapHandler: a
    // handler takes the press even when its grab is only passive, and every
    // module in the open drawer stopped answering clicks.
    //
    // A popup a click opened goes the same way, on a click anywhere but its
    // own module. That click still reaches whatever it landed on, so a click
    // on another module's icon goes straight from one popup to the next.
    MouseArea {
        anchors.fill: parent
        z: 1
        enabled: drawer.open || OpenPopup.owner !== null
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: function (mouse) {
            mouse.accepted = false;
            if (drawer.open && !rightPill.contains(mapToItem(rightPill, mouse.x, mouse.y)))
                drawer.open = false;
            const owner = OpenPopup.owner;
            if (owner && !owner.contains(mapToItem(owner, mouse.x, mouse.y)))
                OpenPopup.close(owner);
        }
    }
}

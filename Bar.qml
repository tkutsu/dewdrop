import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components
import qs.modules
import qs.services as Services

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
    // The pills with their air above and below. The air below is mostly
    // Hyprland's own window gap (general:gaps_out), the same gap that puts a
    // tiled window's left edge level with the left pill, so the bar reserves
    // only what that gap does not already give: the inset less the gap, which
    // at a 5px inset and an 8px gap stops three pixels short of the pills' foot.
    //
    // Once the gaps are off (a lone window, which goes edge to edge on the
    // other three sides) there is no window gap to lean on, and the bar
    // reserves the whole strip the pills sit centred in. Either way the
    // window's top edge ends up at the same line, so the pills keep the same
    // air under them and nothing on the bar changes.
    readonly property int stripHeight: Theme.barHeight + 2 * Theme.barInset
    readonly property int reserved: bar.stripHeight - (bar.gapless ? 0 : Theme.barMargin)
    exclusiveZone: bar.reserved
    // The whole strip, gaps or not: for the glass to bulge into as a drop
    // pours into its neighbour (bar.bulge). Clicks below the pills' foot go through to
    // whatever is under them.
    implicitHeight: bar.stripHeight
    mask: Region {
        width: bar.width
        height: Math.max(bar.reserved, Theme.barInset + Theme.barHeight)
    }
    color: "transparent"

    // Whether Hyprland has taken the gaps off the workspace this bar's monitor
    // is showing. It does that for a lone tiled window and for a fullscreen one
    // — the w[tv1] and f[1] workspace rules in hypr/configs/tags.lua — and the
    // bar reserves the strip in place of the gap (see `reserved`).
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

    // Anywhere on the bar, pills or the air between them. The drawer stays
    // open while the pointer is here or down in one of the bar's popups.
    HoverHandler {
        id: barHover

        onHoveredChanged: PopupPointer.bars += hovered ? 1 : -1
        Component.onDestruction: if (hovered)
            PopupPointer.bars--
    }

    // "fixed-center": true — the centre pill is centred on the bar, not on
    // whatever space the left and right pills happen to leave behind. Three
    // separately anchored islands do that; a single RowLayout would not. Each
    // one places itself from its `side`, which is the same thing that tells it
    // whether it backs onto a screen edge and owes the margin a hit area.
    Pill {
        id: leftPill

        side: Pill.Side.Left
        backdrop: wallpaperImage

        Workspaces {}
    }

    // Glass and badge colours follow the desktop's exact wallpaper blend.
    WallpaperStrip {
        id: wallpaperImage
        anchors.fill: parent
        screen: bar.screen
        atTop: bar.anchors.top
        visible: false
    }

    // The clock's date/time gap sits on the centre line, not the
    // pill around it: the labels either side change width through the
    // week and the month, and centring the pill would have all of it shuffling
    // sideways under a fixed bar.
    // The glass of the clock and of everything that comes and goes beside it,
    // as one surface (see `drop` below). Declared before those pills so it
    // goes under their contents.
    Liquid {
        anchors.fill: parent

        backdrop: wallpaperImage

        // The clock's ends give as a drop goes into them or lets go of them
        // (bar.lip). The notice only touches the clock with no timer set.
        readonly property real leftLip: bar.lip(music.reveal, music.stowed)
        readonly property real rightLip: bar.lip(countdown.reveal, countdown.stowed) + (countdown.reveal > 0 ? 0 : bar.lip(notice.reveal, notice.stowed))

        box0: Qt.vector4d(clockPill.x - leftLip, Theme.barInset, clockPill.width + leftLip + rightLip, Theme.barHeight)
        // The notice after the timer, since that is what it joins.
        box1: bar.countdownDrop
        box2: bar.noticeDrop
        box3: bar.musicDrop
        bulge0: bar.bulge(clockPill.x - leftLip, -1, music.reveal, music.stowed)
        // Whichever is pouring in on the right: the timer into the clock, or
        // the notice into the timer if one is set and the clock if not.
        bulge1: countdown.stowed && countdown.reveal > 0 ? bar.bulge(bar.clockRight + rightLip, 1, countdown.reveal, true) : bar.bulge(countdown.reveal > 0 ? bar.noticeEdge : bar.clockRight + rightLip, 1, notice.reveal, notice.stowed)
        reaches: Qt.vector4d(0, bar.dropReach(countdown.reveal, countdown.stowed), bar.dropReach(notice.reveal, notice.stowed), bar.dropReach(music.reveal, music.stowed))
    }

    Pill {
        id: clockPill

        drawsSlab: false
        side: Pill.Side.Centre
        centreOn: clock.centreItem

        Clock {
            id: clock
        }
    }

    // Everything that comes and goes sits either side of the clock, placed off
    // where the clock pill actually ended up rather than given a Side of its
    // own: the centre pill is not where the centre is — it shifts itself so
    // that the clock's date/time gap lands on the middle of the bar rather than the
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
    // Going away, a pill first lets its contents go, then rushes at the
    // neighbour on its inner side and takes hold of it, still a capsule. It
    // stays a little way off from there, so that what joins the two stays a
    // neck, and pours through it: it drains at an even rate, from its far end
    // in, down to a bead, which the neighbour gulps (see bar.lip for the
    // neighbour's side of it). Moving the whole pill in instead read as one
    // bar getting shorter, a pill disappearing rather than going anywhere.
    //
    // Arriving is not the same run backwards: liquid joins in a hurry and
    // parts reluctantly. The pill comes out of its neighbour round, the neck
    // stretches out before it lets go, and only once it is free does it spring
    // out to its width, past it, and back. `edge` is the neighbour's facing
    // edge, `dir` which way the pill lies from it (1 right, -1 left), `width`
    // the pill at rest, `leaving` whether it is on its way in.
    function drop(edge, dir, width, reveal, leaving) {
        if (reveal <= 0)
            return Qt.vector4d(0, 0, 0, 0);
        const t = 1 - reveal;
        const height = Theme.barHeight;
        // How far this side of the neighbour's edge the pill's inner end is.
        let gap, w, h;
        if (leaving) {
            const c = Math.max(0, Math.min(1, (t - bar.settle) / 0.2));
            const close = 1 - (1 - c) * (1 - c);
            // A capsule while there is enough of it for one, then a ball.
            const full = width * height - (4 - Math.PI) * height * height / 4;
            const bead = Math.PI * Math.pow(0.45 * height, 2) / 4;
            const area = full + (bead - full) * bar.drained(t);
            if (area >= Math.PI * height * height / 4) {
                h = height;
                w = (area + (4 - Math.PI) * height * height / 4) / height;
            } else {
                h = w = Math.sqrt(4 * area / Math.PI);
            }
            // Held off by not quite half the reach the neck is drawn with
            // (bar.dropReach), which keeps it a waist; any closer and it
            // fills out to the pill's height.
            const hold = Theme.pillSpread * 0.6;
            const g = Math.max(0, Math.min(1, (t - 0.78) / 0.14));
            gap = hold + (Theme.pillSpread - hold) * (1 - close) - (height * 1.6 + hold) * g * g;
        } else {
            const close = bar.ease((t - 0.25) / 0.5);
            const plunge = bar.ease((t - 0.65) / 0.35);
            const shrink = 1 - 0.3 * plunge;
            w = (height + (width - height) * bar.spring((0.5 - t) / 0.36)) * shrink;
            h = height * shrink;
            gap = Theme.pillSpread * (1 - close) - height * 1.6 * plunge;
        }
        const inner = edge + dir * gap;
        return Qt.vector4d(dir > 0 ? inner : inner - w, Theme.barInset + (height - h) / 2, w, h);
    }

    // How much of a leaving pill has poured into its neighbour, 0..1.
    function drained(t) {
        return Math.max(0, Math.min(1, (t - 0.25) / 0.55));
    }

    // How far the neighbour's end is pushed out by a drop at a given
    // `reveal`. Going in, it swells with what has poured into it, up to a few
    // pixels, and springs back once the last of it is gulped. Letting go, it
    // gives a little the other way.
    function lip(reveal, leaving) {
        const t = 1 - reveal;
        return leaving ? 3 * bar.drained(t) * (1 - bar.spring((t - 0.85) / 0.15)) : bar.wobble((0.45 - t) / 0.3, -3);
    }

    // Where the neighbour's glass bulges, above and below, as a drop pours
    // into it: a round swelling at its end, a pill's height long, standing
    // under a pixel proud of the slab by the time the last of the drop is in,
    // and springing back with the end (bar.lip). `end` is the neighbour's end the drop is on,
    // `dir` which way the drop lies from it, as for `drop`.
    function bulge(end, dir, reveal, leaving) {
        const t = 1 - reveal;
        const swell = leaving ? 0.75 * bar.drained(t) * (1 - bar.spring((t - 0.85) / 0.15)) : 0;
        if (swell <= 0)
            return Qt.vector4d(0, 0, 0, 0);
        const w = Theme.barHeight;
        return Qt.vector4d(dir > 0 ? end - w : end, Theme.barInset - swell, w, Theme.barHeight + 2 * swell);
    }

    // How far a drop reaches for its neighbour. At rest, the air between
    // them, so the two are drawn exactly as they are. Half again as far while
    // it is on the move, so the neck takes hold while the pill is still a
    // capsule — as soon as it sets off, going in — and back to the air by the
    // time it is inside, so nothing jumps when it goes.
    function dropReach(reveal, leaving) {
        const t = 1 - reveal;
        const reaching = leaving ? bar.ease((t - bar.settle) / 0.2) * (1 - bar.ease((t - 0.85) / 0.15)) : bar.ease((t - 0.25) / 0.3) * (1 - bar.ease((t - 0.8) / 0.2));
        return Theme.pillSpread * (1 + 0.5 * reaching);
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

    // 0 to 1 the way a spring gets there: past it by about 13%, back a touch
    // short, and on it. Near the pill width spring (Theme.foldDamping).
    function spring(x) {
        if (x >= 1)
            return 1;
        const c = Math.max(0, x);
        return 1 - Math.exp(-6 * c) * Math.cos(3 * Math.PI * c);
    }

    // A wobble of `size` over 0..1, at rest at both ends: out, back past
    // rest, and out a little again.
    function wobble(x, size) {
        const c = Math.max(0, Math.min(1, x));
        return size * Math.exp(-3 * c) * Math.sin(3 * Math.PI * c);
    }

    readonly property real clockLeft: clockPill.x
    readonly property real clockRight: clockPill.x + clockPill.width

    readonly property vector4d musicDrop: bar.drop(bar.clockLeft, -1, musicPill.width, music.reveal, music.stowed)
    readonly property vector4d countdownDrop: bar.drop(bar.clockRight, 1, countdownPill.width, countdown.reveal, countdown.stowed)
    // The notice is placed off the timer's glass rather than the clock's, so
    // it goes into the timer while one is set and follows it in as it goes.
    // Once the timer is inside the clock its far edge is too, and the clock's
    // edge is the one to go by.
    readonly property real noticeEdge: countdown.reveal > 0 ? Math.max(bar.clockRight, countdownDrop.x + countdownDrop.z) : bar.clockRight
    readonly property vector4d noticeDrop: bar.drop(bar.noticeEdge, 1, noticePill.width, notice.reveal, notice.stowed)

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
        // With nothing to play there is no pill, rather than an empty one. Off
        // the module's `reveal` rather than its visibility: hiding an item
        // hides its children with it, so a pill reading its child's `visible`
        // would latch shut the first time mpd was quiet.
        visible: music.reveal > 0
        progress: music.progress
        rate: music.rate
        trackColor: music.accent
        trackOpacity: contentOpacity
        trackWidth: music.handsOut ? Theme.pillTrack * 2 : Theme.pillTrack

        Behavior on trackWidth {
            enabled: music.settled
            NumberAnimation {
                duration: Theme.foldMs
                easing.type: Easing.InOutCubic
            }
        }

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
        visible: countdown.reveal > 0
        progress: countdown.progress
        rate: countdown.rate
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
        backdrop: wallpaperImage
        order: RightPillOrder.keys
        readonly property bool languageAtLauncher: shown[shown.length - 2] === language

        // Whatever has nothing to say right now folds away behind this handle,
        // each module in its own place in the row so that opening the drawer
        // puts the pill back exactly as it always was. The modules decide what
        // "nothing to say" is (BarItem.quiet), a middle click can overrule them
        // either way (DrawerPins), and the drawer only decides whether they
        // are showing anyway.
        readonly property var drawable: [audio, email, tasks, updater, bell, weather, satty, idle, wallpaper, night, sys, language]

        // The glass running on past the drawer as its spring carries it out,
        // or squeezing in past shut as it carries it in, and first winding up
        // the other way before either (Drawer.windup).
        stretch: drawable.reduce((sum, m) => sum + (m.here ? m.overrun : 0), drawer.windup)

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
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
            Layout.rightMargin: -1
        }
        Email {
            id: email
            pinKey: "email"
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
        }
        Tasks {
            id: tasks
            pinKey: "tasks"
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
        }
        Updater {
            id: updater
            pinKey: "updater"
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
        }
        NotificationBell {
            id: bell
            pinKey: "bell"
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
        }
        Weather {
            id: weather
            pinKey: "weather"
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
        }
        Satty {
            id: satty
            pinKey: "satty"
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
        }
        IdleInhibit {
            id: idle
            pinKey: "idle"
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
        }
        Wallpaper {
            id: wallpaper
            pinKey: "wallpaper"
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
        }
        NightMode {
            id: night
            pinKey: "night"
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
        }
        Sys {
            id: sys
            pinKey: "sys"
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
        }
        // Connectivity and the tray stay visible as the drawer folds away.
        Bluetooth { id: bluetooth }
        Network { id: network }
        Tray {
            settingsKey: "tray"
        }
        // Every Glyph on the bar is laid out on its ink, but the language
        // label is text and keeps its advance, which leaves about a pixel
        // of side bearing to the right of the "N". That pixel comes back
        // out, and one more beside the launcher: its ring meets the N's
        // straight stem only at its middle, and at the measured gap the pair
        // read as further apart than their neighbours. Trimming the gap
        // rather than shifting the label keeps the module's own width fixed,
        // so nothing moves when the layout changes.
        Language {
            id: language
            pinKey: "language"
            quiet: true
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
            Layout.leftMargin: -1
            Layout.rightMargin: rightPill.languageAtLauncher ? -2 : -1
        }
        LauncherButton {
            Layout.leftMargin: -1
        }
    }

    Connections {
        target: OpenPopup

        function onControlRequested(key: string, screenName: string): void {
            if (bar.modelData.name !== screenName)
                return;
            const item = { sound: audio, display: night, network, bluetooth, notifications: bell }[key];
            if (!item?.here)
                return;
            controlOpen.interval = item.stowed ? Theme.windupMs + Theme.foldLandMs : 1;
            controlOpen.item = item;
            if (item.stowed)
                drawer.open = true;
            controlOpen.restart();
        }
    }

    // Anchor a requested popup after its drawer slot has finished unfolding.
    Timer {
        id: controlOpen
        property var item: null
        onTriggered: {
            if (item?.here && !item.stowed)
                OpenPopup.set(item);
            item = null;
        }
    }

    // A click anywhere on the bar but the right pill puts the drawer away,
    // the way a menu bar's extras fold back once you click on something else.
    // A click in another window is Drawer.qml's, off Hyprland's click event.
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

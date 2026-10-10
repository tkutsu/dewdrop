import QtQuick
import QtQuick.Layouts
import Quickshell
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
    // Below windows, so one dragged up over the bar passes over it; tiled
    // windows never reach it anyway, the exclusive zone keeps them clear. The
    // popups are xdg popups of this surface and share its layer, so while one
    // is up, or the pointer is on the bar where a tooltip may open, the bar
    // comes up to Top or the popups would drop behind the windows under them.
    // A drag starts with a click, which closes the open popup first.
    WlrLayershell.layer: raise.active ? WlrLayer.Top : WlrLayer.Bottom

    // Held through a popup's fade out, which is drawn on this layer too.
    Linger {
        id: raise

        shown: OpenPopup.owner !== null || barHover.hovered || PopupPointer.hovered > 0
    }

    // The keyboard, while one of this bar's popups is open, for the popup to
    // be driven from (Popup.qml): the popup's own surface gets no keys
    // without a grab. Exclusive rather than on-demand because the click that
    // opened the popup has already happened by the time this turns on; the
    // window under the bar has its keyboard back the moment the popup goes.
    // And while the bar itself is walked from the keyboard (selection mode,
    // OpenPopup.selected), down in a popup or not.
    readonly property bool keyed: (OpenPopup.keyed.length > 0 && OpenPopup.owner?.QsWindow.window === bar) || OpenPopup.selected?.QsWindow.window === bar
    WlrLayershell.keyboardFocus: bar.keyed ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Item {
        focus: true
        Keys.onPressed: event => event.accepted = OpenPopup.selected !== null && !OpenPopup.inPopup ? bar.selectKey(event) : OpenPopup.key(event)
    }

    // Selection mode's keys while they are on the bar rather than in a popup
    // (see OpenPopup.select).
    function selectKey(event: var): bool {
        const item = OpenPopup.selected;
        switch (event.key) {
        case Qt.Key_Escape:
            OpenPopup.dismiss();
            return true;
        case Qt.Key_Left:
        case Qt.Key_Right:
            {
                // Round from one end to the other, the way a menu bar goes.
                const stops = bar.stops();
                const step = event.key === Qt.Key_Right ? 1 : -1;
                const at = stops.indexOf(item);
                const next = at < 0 ? stops[step > 0 ? 0 : stops.length - 1] : stops[(at + step + stops.length) % stops.length];
                if (next)
                    OpenPopup.select(next);
                return true;
            }
        case Qt.Key_Down:
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (item.keyOpens)
                OpenPopup.enter();
            else if (event.key !== Qt.Key_Down)
                item.keyPress();
            return true;
        }
        return false;
    }

    // The items selection mode stops at, left to right: whatever has a
    // popup to open or a press to make (OpenPopup.select), and is on the
    // bar rather than folded away.
    function stops(): var {
        const found = [];
        const walk = item => {
            for (const child of item.children) {
                if (!child.visible || child.opacity === 0)
                    continue;
                if ((child.keyOpens === true || typeof child.keyPress === "function") && child.width > 0)
                    found.push(child);
                walk(child);
            }
        };
        walk(bar.contentItem);
        const at = new Map(found.map(s => [s, s.mapToItem(bar.contentItem, s.width / 2, 0).x]));
        return found.sort((a, b) => at.get(a) - at.get(b));
    }

    // The launcher puts popups away as it opens; the power menu and the
    // settings window want the keyboard as well, so they end selection mode.
    readonly property bool overlayUp: Services.Power.active || Services.Preferences.active
    onOverlayUpChanged: if (overlayUp && OpenPopup.selected?.QsWindow.window === bar)
        OpenPopup.dismiss()

    anchors {
        top: true
        left: true
        right: true
    }
    // The pills with their air above and below. The air below is mostly
    // Hyprland's own window gap (general:gaps_out), the same gap that puts a
    // tiled window's left edge level with the left pill, so the bar reserves
    // only what that gap does not already give: the inset less the gap, which
    // at a 4px inset and an 8px gap stops four pixels short of the pills' foot.
    //
    // A lone or fullscreen window goes edge to edge on the other three sides
    // but keeps that top gap (the smart-gaps rules in hypr/configs/tags.lua),
    // so every window's top edge lands on the same line and the reserve never
    // changes. It used to, with the bar guessing which rule Hyprland applied,
    // and a tooltip opening as a window of its own made it guess wrong for a
    // frame and bounced the window under it.
    readonly property int stripHeight: Theme.barHeight + 2 * Theme.barInset
    readonly property int reserved: bar.stripHeight - Theme.barMargin
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

    // Weather sits on the centre line between the date and time:
    // the labels either side change width through the
    // week and the month, and centring the pill would have all of it shuffling
    // sideways under a fixed bar.
    // The glass of the clock and of everything that comes and goes beside it,
    // as one surface (see `drop` below). Declared before those pills so it
    // goes under their contents.
    Liquid {
        anchors.fill: parent

        backdrop: wallpaperImage

        // The clock's ends give as a drop goes into them or lets go of them
        // (bar.lip).
        readonly property real leftLip: bar.lip(music.reveal, music.stowed)
        readonly property real rightLip: bar.lip(countdown.reveal, countdown.stowed)

        box0: Qt.vector4d(clockPill.x - leftLip, Theme.barInset, clockPill.width + leftLip + rightLip, Theme.barHeight)
        box1: bar.countdownDrop
        box3: bar.musicDrop
        bulge0: bar.bulge(clockPill.x - leftLip, -1, music.reveal, music.stowed)
        bulge1: bar.bulge(bar.clockRight + rightLip, 1, countdown.reveal, countdown.stowed)
        reaches: Qt.vector4d(0, bar.dropReach(countdown.reveal, countdown.stowed), 0, bar.dropReach(music.reveal, music.stowed))
    }

    Pill {
        id: clockPill

        drawsSlab: false
        side: Pill.Side.Centre
        centreOn: weather.here ? weather : null

        Clock {
            id: clock
        }

        Weather {
            id: weather
        }

        BarItem {
            name: "Timers"
            popup: TimerPopup {}
            actions: clock.actions

            RollingText {
                Layout.fillHeight: true
                text: Qt.formatDateTime(clock.date, Settings.timeFormat)
            }
        }
    }

    // Everything that comes and goes sits either side of the clock, placed off
    // where the clock pill actually ended up rather than given a Side of its
    // own: the centre pill is not where the centre is — it shifts itself so
    // that weather lands on the middle of the bar rather than the
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
    // Going away, a pill first lets its contents go, then gathers itself up
    // off its far end into a bead, the way a stretched-out drop pulls round,
    // and wobbles as it rounds. Only then does it fall into the neighbour: the
    // neck fills out to the bead's height a frame or two after they touch, as
    // water does, and the neighbour takes what came in as a swelling of its
    // end that springs back (bar.lip, bar.bulge). It never stays joined by a
    // waist: held there, it read as being sucked through a straw.
    //
    // Arriving is not the same run backwards: liquid joins in a hurry and
    // parts reluctantly. The neighbour's end swells and a bud grows out of
    // it, the neck draws out and thins until it lets go, the freed bead rounds
    // off, and only then does it spring out to its width, past it, and back,
    // at rest before its contents come in. `edge` is the neighbour's facing
    // edge, `dir` which way the pill lies from it (1 right, -1 left), `width`
    // the pill at rest, `leaving` whether it is on its way in.
    function drop(edge, dir, width, reveal, leaving) {
        if (reveal <= 0)
            return Qt.vector4d(0, 0, 0, 0);
        const t = 1 - reveal;
        const height = Theme.barHeight;
        const bead = bar.bead;
        // How far this side of the neighbour's edge the pill's inner end is.
        let gap, w, h, squash;
        if (leaving) {
            w = width + (bead - width) * bar.ease((t - bar.settle) / 0.3);
            h = Math.min(height, Math.max(bead, w));
            squash = bar.wobble((t - 0.42) / 0.3, 0.1);
            const fall = Math.pow(Math.max(0, Math.min(1, (t - 0.5) / 0.2)), 2);
            // All the way in: the bead ends up inside the neighbour's round end.
            gap = Theme.pillSpread - (Theme.pillSpread + bead + 3) * fall;
        } else {
            const bud = 1 - Math.pow(1 - Math.min(1, reveal / 0.4), 2);
            gap = -bead - 2 + (Theme.pillSpread + bead + 2) * bud;
            // What is left of the spring by the time the contents come in is
            // let go of, so they come in over glass at rest.
            const grow = 1 + (bar.spring((reveal - 0.42) / 0.14) - 1) * (1 - bar.ease((reveal - 0.72) / 0.1));
            w = bead + (width - bead) * grow;
            h = bead + (height - bead) * Math.min(1, grow * 3);
            squash = reveal < 0.55 ? bar.wobble((reveal - 0.3) / 0.25, 0.08) : 0;
        }
        w *= 1 - squash;
        h *= 1 + squash / 2;
        if (!leaving)
            w = Math.max(w, h);
        const inner = edge + dir * gap;
        return Qt.vector4d(dir > 0 ? inner : inner - w, Theme.barInset + (height - h) / 2, w, h);
    }

    // A drop gathered up: a little shorter than a pill, so the neck that
    // joins it to the neighbour is a neck and not a straight run of glass.
    readonly property int bead: Math.round(Theme.barHeight * 0.8)

    // How far the neighbour's end is pushed out by a drop at a given
    // `reveal`. Going in, it is shoved out by the bead and wobbles back.
    // Coming out, it is drawn out with the bud and snaps back past rest as
    // the bud lets go.
    function lip(reveal, leaving) {
        if (leaving)
            return bar.wobble((0.38 - reveal) / 0.38, 5);
        const drawn = 1 - Math.pow(1 - Math.min(1, reveal / 0.2), 2);
        return 3 * drawn * (1 - bar.ease((reveal - 0.2) / 0.12)) + bar.wobble((reveal - 0.3) / 0.35, -2.5);
    }

    // Where the neighbour's glass bulges, above and below, at the end a drop
    // goes into or comes out of: once, as the bead goes in or the bud swells,
    // a pixel or so proud of the slab. `end` is the neighbour's end the drop
    // is on, `dir` which way the drop lies from it, as for `drop`.
    function bulge(end, dir, reveal, leaving) {
        const x = leaving ? (0.36 - reveal) / 0.12 : reveal / 0.32;
        const swell = (leaving ? 1.2 : 1.5) * Math.sin(Math.PI * Math.max(0, Math.min(1, x)));
        if (swell <= 0)
            return Qt.vector4d(0, 0, 0, 0);
        const w = Theme.barHeight * 1.2;
        return Qt.vector4d(dir > 0 ? end - w : end, Theme.barInset - swell, w, Theme.barHeight + 2 * swell);
    }

    // How far a drop reaches for its neighbour. At rest, the air between
    // them, so the two are drawn exactly as they are. Going in, it lets go of
    // the neighbour's end once the bead is inside it, or the end swelled out
    // square against the top and bottom of the slab. Coming out, it reaches
    // further while the bud is pinching off, so the neck draws out thin
    // before it breaks.
    function dropReach(reveal, leaving) {
        if (leaving)
            return Theme.pillSpread * (1 - 0.8 * bar.ease((0.36 - reveal) / 0.08));
        return Theme.pillSpread * (0.25 + 1.25 * bar.ease(reveal / 0.12) - 0.5 * bar.ease((reveal - 0.35) / 0.15));
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

    // 0 to 1 the way a spring let go from rest gets there: slow off the
    // mark, on it at 1, past it by about 13% at 1.5, and settled by 4.4.
    // A spring that set off at speed jumped most of the way in one frame.
    function spring(x) {
        const c = Math.max(0, x) * 0.227;
        if (c >= 1)
            return 1;
        const k = 3 * Math.PI;
        return 1 - Math.exp(-6 * c) * (Math.cos(k * c) + 6 / k * Math.sin(k * c));
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
    // format does — the figures are tabular — so it does not twitch once a
    // second.
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
        trackWidth: countdown.handsOut ? Theme.pillTrack * 2 : Theme.pillTrack

        Behavior on trackWidth {
            enabled: countdown.settled
            NumberAnimation {
                duration: Theme.foldMs
                easing.type: Easing.InOutCubic
            }
        }

        Countdown {
            id: countdown
            foldDuration: Theme.dropMs
            foldEasing: Easing.Linear
        }
    }

    // The recording pill and the notice come out of the right pill the way
    // the clock's neighbours come out of the clock (bar.drop). The right pill
    // draws its own glass, which ends at its edge, so while either is out the
    // bar draws them all as one surface here instead, and the right pill
    // stands its own slab down (drawsSlab below). Declared before all three,
    // so it lies under their contents.
    readonly property rect rightGlass: rightPill.slabRect
    readonly property bool rightPouring: recording.reveal > 0 || notice.reveal > 0
    readonly property vector4d recordingDrop: bar.drop(bar.rightGlass.x, -1, recordingPill.width, recording.reveal, recording.stowed)
    // The notice is placed off the recording pill's glass while it is out, so
    // it goes into that pill and follows it in as it goes; once that pill is
    // inside the right one, the right pill's edge is the one to go by.
    readonly property real noticeEdge: recording.reveal > 0 ? Math.min(bar.rightGlass.x, recordingDrop.x) : bar.rightGlass.x
    readonly property vector4d noticeDrop: bar.drop(bar.noticeEdge, -1, noticePill.width, notice.reveal, notice.stowed)

    Liquid {
        anchors.fill: parent
        visible: bar.rightPouring

        backdrop: wallpaperImage

        // The right pill's end gives as a drop goes into it (bar.lip). The
        // notice only touches it with the recording pill away.
        readonly property real lip: bar.lip(recording.reveal, recording.stowed) + (recording.reveal > 0 ? 0 : bar.lip(notice.reveal, notice.stowed))

        box0: Qt.vector4d(bar.rightGlass.x - lip, Theme.barInset, bar.rightGlass.width + lip, Theme.barHeight)
        box1: bar.recordingDrop
        box2: bar.noticeDrop
        // Whichever is pouring in: the recording pill into the right pill,
        // or the notice into the recording pill if it is out and the right
        // pill if not.
        bulge0: recording.stowed && recording.reveal > 0 ? bar.bulge(bar.rightGlass.x - lip, -1, recording.reveal, true) : bar.bulge(recording.reveal > 0 ? bar.noticeEdge : bar.rightGlass.x - lip, -1, notice.reveal, notice.stowed)
        reaches: Qt.vector4d(0, bar.dropReach(recording.reveal, recording.stowed), bar.dropReach(notice.reveal, notice.stowed), 0)
    }

    Pill {
        id: recordingPill

        edges: false
        drawsSlab: false
        contentOpacity: bar.contents(recording.reveal)

        side: Pill.Side.Right
        edgeOffset: bar.width - bar.rightGlass.x + Theme.pillSpread
        visible: recording.reveal > 0

        Recording {
            id: recording
            foldDuration: Theme.dropMs
            foldEasing: Easing.Linear
        }
    }

    // A notification as it comes in, outermost on this side: left of the
    // recording pill when one is out, of the right pill when not. Placed off
    // that glass (bar.noticeEdge), so the two arrive and leave in step.
    // Anchored by its right edge, so it grows away from the right pill, and
    // it may run as far as a spread short of the clock or the timer beside
    // it: someone else's text, but read once and then gone, so it gets all
    // the room there is rather than a fixed ceiling.
    Pill {
        id: noticePill

        edges: false
        drawsSlab: false
        contentOpacity: bar.contents(notice.reveal)

        side: Pill.Side.Right
        edgeOffset: bar.width - bar.noticeEdge + Theme.pillSpread
        // Off the module's `reveal`, never its visibility (see the music pill
        // above).
        visible: notice.reveal > 0

        Notice {
            id: notice
            foldDuration: Theme.dropMs
            foldEasing: Easing.Linear
            room: bar.noticeEdge - Theme.pillSpread - ((countdown.reveal > 0 ? countdownPill.x + countdownPill.width : bar.clockRight) + Theme.pillSpread)
        }
    }

    Pill {
        id: rightPill

        side: Pill.Side.Right
        backdrop: wallpaperImage
        drawsSlab: !bar.rightPouring
        order: RightPillOrder.keys
        readonly property bool languageAtLauncher: shown[shown.length - 2] === language

        // Whatever has nothing to say right now folds away behind this handle,
        // each module in its own place in the row so that opening the drawer
        // puts the pill back exactly as it always was. The modules decide what
        // "nothing to say" is (BarItem.quiet), a middle click can overrule them
        // either way (DrawerPins), and the drawer only decides whether they
        // are showing anyway.
        readonly property var drawable: [audio, email, tasks, updater, bell, satty, idle, wallpaper, night, sys, settings, drives, bluetooth, network, tray, language]

        // The glass running on past the drawer as its spring carries it out,
        // or squeezing in past shut as it carries it in, and first winding up
        // the other way before either (Drawer.windup).
        stretch: drawable.reduce((sum, m) => sum + (m.here ? m.overrun : 0), drawer.windup)

        Drawer {
            id: drawer
            // A tray icon kept in counts, though the tray itself is out.
            holding: rightPill.drawable.some(m => m.here && !m.showsClosed) || (tray.here && tray.tucks)
            // Or a popup is open: one of the drawer's own modules would fold
            // away from under it.
            pointerNear: barHover.hovered || PopupPointer.hovered > 0 || OpenPopup.owner !== null || OpenPopup.selected !== null
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
        SettingsButton {
            id: settings
            pinKey: "settings"
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
        }
        Drives {
            id: drives
            pinKey: "drives"
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
        }
        // Connectivity and the tray have always something to say, so they
        // stay out as the drawer folds away unless kept in (DrawerPins).
        Bluetooth {
            id: bluetooth
            pinKey: "bluetooth"
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
        }
        Network {
            id: network
            pinKey: "network"
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
        }
        Tray {
            id: tray
            pinKey: "tray"
            drawerOut: drawer.out
            stowed: !showsClosed && !drawer.out
            marksPin: drawer.out
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

    // Selection mode starts on the calendar, popup open.
    Connections {
        target: OpenPopup

        function onSelectRequested(screenName: string): void {
            if (bar.modelData.name === screenName)
                OpenPopup.select(clock);
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
    // Any click on the bar ends selection mode, and hands it the pointer.
    MouseArea {
        anchors.fill: parent
        z: 1
        enabled: drawer.open || OpenPopup.owner !== null || OpenPopup.selected !== null
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: function (mouse) {
            mouse.accepted = false;
            OpenPopup.deselect();
            if (drawer.open && !rightPill.contains(mapToItem(rightPill, mouse.x, mouse.y)))
                drawer.open = false;
            const owner = OpenPopup.owner;
            if (owner && !owner.contains(mapToItem(owner, mouse.x, mouse.y)))
                OpenPopup.close(owner);
        }
    }
}

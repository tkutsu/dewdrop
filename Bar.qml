import "KeyTargets.js" as KeyTargets
import "Drops.js" as Drops
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

    readonly property var drops: Drops.geometry(Theme)
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

    // Acquire focus for a click-opened popup, then let outside clicks focus their target.
    readonly property bool keyed: (OpenPopup.keyed.length > 0 && OpenPopup.owner?.QsWindow.window === bar) || OpenPopup.selected?.QsWindow.window === bar
    property bool acquiringFocus: false
    onKeyedChanged: bar.acquiringFocus = bar.keyed && !keyReceiver.activeFocus
    WlrLayershell.keyboardFocus: bar.keyed && bar.acquiringFocus ? WlrKeyboardFocus.Exclusive
        : bar.keyed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    PopupKeyRelay {
        id: keyReceiver
        onActiveFocusChanged: if (activeFocus && bar.acquiringFocus)
            Qt.callLater(() => bar.acquiringFocus = false)
        input: OpenPopup.keyed.length ? OpenPopup.keyed[OpenPopup.keyed.length - 1].keyInput : null
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
        const found = KeyTargets.collect(bar.contentItem, child => (child.keyOpens === true || typeof child.keyPress === "function") && child.width > 0);
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
    // pours into its neighbour (Drops.js bulge). Clicks below the pills' foot go through to
    // whatever is under them.
    implicitHeight: bar.stripHeight
    mask: Region {
        width: bar.width
        height: Math.max(bar.reserved, Theme.barInset + Theme.barHeight)
    }
    color: "transparent"

    // Anywhere on the bar, pills or the air between them. The drawer stays
    // open while the pointer is here or down in one of the bar's popups, and
    // the glass catches its light (GlassLight).
    HoverHandler {
        id: barHover

        onPointChanged: if (hovered)
            GlassLight.track(bar, point.position)
        onHoveredChanged: {
            PopupPointer.bars += hovered ? 1 : -1;
            if (!hovered)
                GlassLight.leave(bar);
        }
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

        Workspaces {
            id: workspaces
            drawsMark: !glassMark.active
        }
    }

    // The workspace mark's glass, over the pill it moves in, which it bends.
    GlassMark {
        id: glassMark
        x: leftPill.x
        y: leftPill.y
        width: leftPill.width
        height: leftPill.height
        mark: workspaces.markItem
        pillItem: leftPill
        wallpaperItem: wallpaperImage
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
        // (Drops.js lip). The notice only touches the clock with no timer set.
        readonly property real leftLip: bar.drops.lip(music.reveal, music.stowed)
        readonly property real rightLip: bar.drops.lip(countdown.reveal, countdown.stowed) + (countdown.reveal > 0 ? 0 : bar.drops.lip(notice.reveal, notice.stowed))

        box0: Qt.vector4d(clockPill.x - leftLip, Theme.barInset, clockPill.width + leftLip + rightLip, Theme.barHeight)
        box1: bar.countdownDrop
        box2: bar.noticeDrop
        box3: bar.musicDrop
        overflow: Qt.vector4d(0, 1, 0, 1)
        bulge0: bar.drops.bulge(clockPill.x - leftLip, -1, music.reveal, music.stowed)
        // The timer joins the clock; the notice joins the timer if present.
        bulge1: countdown.stowed && countdown.reveal > 0 ? bar.drops.bulge(bar.clockRight + rightLip, 1, countdown.reveal, true) : bar.drops.bulge(countdown.reveal > 0 ? bar.noticeEdge : bar.clockRight + rightLip, 1, notice.reveal, notice.stowed)
        reaches: Qt.vector4d(0, bar.drops.dropReach(countdown.reveal, countdown.stowed), bar.drops.dropReach(notice.reveal, notice.stowed), bar.drops.dropReach(music.reveal, music.stowed))
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
                readonly property var display: Settings.clockDisplay(clock.date)
                text: display.text
                smallRanges: display.smallRanges
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
    // the clock), and each pill's share of it is a box worked out by Drops.js `drop`
    // from the module's own `reveal`, the same eased 0..1 the drawer folds on.
    //
    // Going away, a pill first lets its contents go, then gathers itself up
    // off its far end into a bead, the way a stretched-out drop pulls round,
    // and wobbles as it rounds. Only then does it fall into the neighbour: the
    // neck fills out to the bead's height a frame or two after they touch, as
    // water does, and the neighbour takes what came in as a swelling of its
    // end that springs back (Drops.js lip, bulge). It never stays joined by a
    // waist: held there, it read as being sucked through a straw.
    //
    // Arriving is not the same run backwards: liquid joins in a hurry and
    // parts reluctantly. The pill comes out of its neighbour round, the neck
    // stretches out before it lets go, and only once it is free does it spring
    // out to its width, past it, and back.

    readonly property real clockLeft: clockPill.x
    readonly property real clockRight: clockPill.x + clockPill.width

    readonly property vector4d musicDrop: bar.drops.morph(bar.drops.drop(bar.clockLeft, -1, musicPill.width, music.reveal, music.stowed), musicMorph.value)
    readonly property vector4d countdownDrop: bar.drops.morph(bar.drops.drop(bar.clockRight, 1, countdownPill.width, countdown.reveal, countdown.stowed), countdownMorph.value)

    // The music and timer pills turn into their popovers rather than opening
    // them (Popup.morphs): the pill's contents go, its glass gathers into a
    // drop at its middle and starts sinking halfway through gathering. It
    // sinks through the slab's foot, where the bar's glass ends, into the
    // popover coming out under it.
    Morph {
        id: musicMorph
        open: music.popupOpen
    }
    Morph {
        id: countdownMorph
        open: countdown.popupOpen
    }
    // Follow the timer's glass as it arrives or leaves, falling back to the
    // clock's right edge once the timer is inside it.
    readonly property real noticeEdge: countdown.reveal > 0 ? Math.max(bar.clockRight, countdownDrop.x + countdownDrop.z) : bar.clockRight
    readonly property vector4d noticeDrop: bar.drops.drop(bar.noticeEdge, 1, noticePill.width, notice.reveal, notice.stowed)

    // The player, alone on the clock's left. What it carries is a song title —
    // text from somewhere else, as long as whoever named the track made it —
    // and nothing else should have to move along every time a new one starts:
    // it is anchored by its right edge, so a longer title only grows it
    // outwards.
    //
    // The pills stay where they rest while their glass runs off from under
    // them; their contents have gone by then (Drops.js contents).
    SidePill {
        id: musicPill
        control: music
        morphValue: musicMorph.value

        side: Pill.Side.Right
        edgeOffset: bar.width - bar.clockLeft + Theme.pillSpread
        progress: music.progress
        rate: music.rate
        trackColor: music.accent
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
    SidePill {
        id: countdownPill
        control: countdown
        morphValue: countdownMorph.value

        side: Pill.Side.Left
        edgeOffset: bar.clockRight + Theme.pillSpread
        progress: countdown.progress
        rate: countdown.rate
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

    // The recording pill comes out of the right pill (bar.drop). While it
    // is out, this surface draws both pills and the right pill stands its
    // own slab down. Declared before both to lie under their contents.
    readonly property rect rightGlass: rightPill.slabRect
    readonly property vector4d recordingDrop: bar.drops.drop(bar.rightGlass.x, -1, recordingPill.width, recording.reveal, recording.stowed)

    Liquid {
        anchors.fill: parent
        visible: recording.reveal > 0

        backdrop: wallpaperImage

        readonly property real lip: bar.drops.lip(recording.reveal, recording.stowed)

        box0: Qt.vector4d(bar.rightGlass.x - lip, Theme.barInset, bar.rightGlass.width + lip, Theme.barHeight)
        box1: bar.recordingDrop
        bulge0: bar.drops.bulge(bar.rightGlass.x - lip, -1, recording.reveal, recording.stowed)
        reaches: Qt.vector4d(0, bar.drops.dropReach(recording.reveal, recording.stowed), 0, 0)
    }

    SidePill {
        id: recordingPill
        control: recording

        side: Pill.Side.Right
        edgeOffset: bar.width - bar.rightGlass.x + Theme.pillSpread

        Recording {
            id: recording
            foldDuration: Theme.dropMs
            foldEasing: Easing.Linear
        }
    }

    // A notice grows rightwards from the timer's glass, or the clock's when
    // no timer is present. Leave a spread before the recording or right pill.
    SidePill {
        id: noticePill
        control: notice

        side: Pill.Side.Left
        edgeOffset: bar.noticeEdge + Theme.pillSpread

        Notice {
            id: notice
            foldDuration: Theme.dropMs
            foldEasing: Easing.Linear
            room: (recording.reveal > 0 ? recordingPill.x : rightPill.x) - Theme.pillSpread - (bar.noticeEdge + Theme.pillSpread)
        }
    }

    Pill {
        id: rightPill

        side: Pill.Side.Right
        backdrop: wallpaperImage
        drawsSlab: recording.reveal <= 0
        order: RightPillOrder.keys
        readonly property bool languageAtLauncher: shown[shown.length - 2] === language

        // Whatever has nothing to say right now folds away behind this handle,
        // each module in its own place in the row so that opening the drawer
        // puts the pill back exactly as it always was. The modules decide what
        // "nothing to say" is (BarItem.quiet), a middle click can overrule them
        // either way (DrawerPins), and the drawer only decides whether they
        // are showing anyway.
        readonly property var drawable: rightPill.modules

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
            const moduleKey = {sound: "audio", display: "night", notifications: "bell"}[key] ?? key;
            const item = rightPill.drawable.find(item => item.pinKey === moduleKey);
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

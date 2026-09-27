pragma Singleton

import QtQuick
import Quickshell

// Single source of truth for everything the old style.css and the Pango markup
// in config.jsonc used to carry. Values here are the waybar ones converted to
// pixels once, rather than re-derived per module.
Singleton {
    // --- metrics -------------------------------------------------------------
    // Every one of these is an integer on purpose. waybar's rem-derived values
    // land on fractions (0.5rem is 7.33px), and a fractional module width puts
    // everything downstream of it on a half pixel, which is what turns a 14px
    // icon into a smudge. Nothing here is allowed to be fractional, and neither
    // is anything derived from it.
    //
    // macOS's menu bar height (24pt since Big Sur). Even, so an icon centres
    // on whole pixels and the pill's round end is exactly half of it. This is
    // the height of a pill rather than of the bar: the layer surface is
    // barMargin taller on each side, and the extra is transparent.
    readonly property int barHeight: 24

    // The bar draws nothing itself; its three groups are three separate pills
    // floating on the wallpaper. This is the air around them — off the screen
    // edges on all four sides, and the least that can ever sit between two
    // pills. Same value all round, so a pill is as far off the top of the
    // screen as it is off the side.
    //
    // Keep it equal to Hyprland's general:gaps_out (hypr/configs/*.lua). The
    // bar does not reserve the air under the pills; that is the window gap,
    // and the two only match while these two numbers do.
    readonly property int barMargin: 4

    // A pill claims the margin around it as hit area, so a module's box is
    // taller than the slab it is drawn on. Everything centres in its box and
    // lands on the slab regardless — this is for the few things that hang off
    // the top edge instead, and need to know where that edge got to.
    function pillTop(boxHeight) {
        return (boxHeight - barHeight) / 2;
    }

    // Fully round ends: half a pill's height. A radius short of that reads as a
    // rounded rectangle, which is the thing the pills are meant not to be.
    readonly property int pillRadius: barHeight / 2

    // How far inside a pill its contents start. It has to clear the rounded end
    // — anything less and the first numeral sits in the curve — and it is what
    // separates two pills' contents on top of the gap between the pills.
    readonly property int pillPad: 10

    // A popup is a slab hung off a pill rather than a pill itself, so it gets a
    // corner rather than a round end. Two sizes, the way macOS draws them: a
    // popover (the calendar, the sliders, the launcher), and a menu — rows of
    // text and nothing else — one step tighter. The selection inside either is
    // a rounded fill inset from the edge, and its radius follows.
    readonly property int popupRadius: 8
    // How far below the slab a popup hangs. The system drops a menu bar's
    // menus flush under the item they came from; this leaves a hairline of
    // wallpaper between the two surfaces so they read as two, and no more.
    // It used to be the whole of barMargin, because the popup hung off the
    // module's box and the box reaches into the margin the pill claims for
    // clicks — which put every menu a click's width away from the click.
    readonly property int popupGap: 2
    readonly property int menuRadius: 5
    readonly property int selectionRadius: 4
    readonly property int selectionInset: 5
    // The rounded fill inside a pill that says "this one": the workspace you
    // are on, and whichever module has its popup open. How far it keeps off
    // the pill's top and bottom edges, and — through pillPad — its ends.
    readonly property int markInset: 3

    // One gap between things that stand on their own: modules, tray icons, one
    // workspace and the next. Measured icon to icon — a badge floats in the gap
    // rather than claiming layout width, so a counted module sits exactly as far
    // from its neighbour as an uncounted one does.
    readonly property int gap: 15

    // Inside a workspace, its number and window icons sit tighter than that, so
    // the workspace reads as one thing rather than as a run of loose icons.
    readonly property int appIconGap: 3

    // The music pill's three controls are one instrument rather than three
    // modules that happen to be neighbours, so they sit closer than `gap` —
    // far enough apart not to run into the title's side bearings, close enough
    // that the two hands read as belonging to the title between them.
    readonly property int mediaGap: 8

    // How wide that title is allowed to run before it elides. Everything else
    // on the bar is as wide as what it has to say; a song title is text from
    // somewhere else and can be any length, and without a ceiling the pill
    // walks across the bar every time a remix credit turns up.
    readonly property int mediaTitleWidth: 170

    // The air between neighbouring islands. Two of waybar's rems (29.33px),
    // rounded to a whole pixel like everything else here: far enough that two
    // pills read as separate islands rather than as one pill with a seam in
    // it, near enough that they still read as neighbours.
    readonly property int pillSpread: 29

    // The pill's outline. Also how far in anything that sits flush against the
    // inside of a pill has to start — the active workspace's rule does.
    readonly property int pillBorder: 1

    // The outline when it is carrying something — the music pill's track
    // position. Half again the hairline, because this one is read rather than
    // only seen, and it is drawn inside the pill's own edge so that reading it
    // costs the bar no height: a pill with a position on it stands exactly as
    // tall as the ones either side of it. Fractional on purpose: with Pill's
    // half-pixel bleed, 1.5 is one whole pixel inside the edge plus the bleed,
    // so the inner edge lands on the grid (2 left it straddling a pixel).
    readonly property real pillTrack: 1.5

    // --- type and icon sizes -------------------------------------------------
    // Named rather than scaled off a base size: Symbols Nerd Font only hints
    // cleanly at some pixel sizes — 11 and 13 come out thin and fuzzy, 12 and 14
    // land on the grid — so the 90%/110%/120% spans in config.jsonc are
    // resolved here once instead of rounding into a blurry 13 at each call site.
    readonly property int textSize: 12
    // The popups' secondary lines — a notification's app and age, the
    // launcher's right-hand hint — one step under their 12px body text.
    readonly property int captionSize: 11
    // Text that has to hold its own in a row of icons rather than stand alone
    // (the language label, the launcher's rows). The same 12 as textSize now
    // that the bar's text came down to 12 too; kept as its own name because
    // it is a different question, and the two have differed before.
    readonly property int labelSize: 12
    // The workspace letters: a step under the clock, so they read as marks
    // on the taskbar rather than as words beside its icons.
    readonly property int workspaceTextSize: 11
    readonly property int glyphSize: 16
    // Glyphs inside a popup, beside its 12px text rather than the bar's.
    readonly property int popupGlyphSize: 14
    readonly property int glyphSizeLarge: 16
    // The glyphs the tray draws in place of nm-applet's artwork. A step under
    // glyphSize: at 16 the wifi cone was 12px of solid ink with its tip a row
    // below the Bluetooth and launcher drawings either side of it, and read a
    // size up from them. At 15 it is 11px and ends on their bottom row.
    readonly property int trayGlyphSize: 15
    // One size for everything the bar draws from artwork rather than from a
    // font — the tray and the workspace taskbar. 18 is the box macOS gives a
    // menu bar item; iconInk decides how much of it the artwork fills.
    //
    // It used to be two, 16 here and 13 for the taskbar, because the two sets
    // are drawn to different conventions: a panel icon keeps margin inside its
    // box, an application icon fills it edge to edge, and the same box gave
    // them visibly different ink. The box is not what decides that any more
    // (see iconInk), so the convention the artwork was drawn to stopped
    // mattering and the second size went with it.
    readonly property int iconSize: 18
    // How tall an icon's ink should stand in its box, measured rather than
    // assumed (components/InkProbe.qml). Thirteen pixels of ink in an
    // eighteen pixel box: level with the bar's 16px glyphs, whose ink comes
    // out at 12 to 14, and deliberately under every icon the theme ships —
    // those come in between 0.75 and 0.97 depending on who drew them, and an
    // app handing the tray one of its own — or a taskbar window icon, which is
    // an application icon and fills its box outright — can reach the full box.
    // Setting the line below all of them is what makes a row even: every icon
    // is pulled down onto it rather than only the ones that overshot, so the
    // tray and the taskbar each stand at one height instead of at the theme's
    // spread of them, and both stand at the same one.
    readonly property real iconInk: 13 / 18
    // The same for a drawing that stands in a glyph's slot (see Glyph): held
    // to twelve pixels, between the glyphs' ten and the tray's artwork, so a
    // row that mixes the two reads as one hand rather than two sizes.
    readonly property real glyphInk: 0.75

    // The count badge on a taskbar icon standing for several windows of one app.
    readonly property int badgeSize: 12
    readonly property int badgeTextSize: 9
    // Where every badge's centre line sits, measured from the top of the pill
    // (see pillTop), so badges line up across the bar whatever size the icon
    // beneath them is.
    readonly property int badgeLine: 8

    // The pin mark on a pinned module's lower right corner, shown while the
    // drawer is open: the badge's dark disc a size down, since it answers a
    // question you only ask with the drawer out.
    readonly property int pinMarkSize: 10
    readonly property int pinGlyphSize: 7

    // Every count on the bar rides the top edge of the pill instead of sitting
    // inside it: half on the slab, half on the margin above, which gives the
    // icon underneath its corner back. A margin's worth of rise is as far as
    // it can go — any higher and the badge is drawn outside the layer surface
    // and loses its top.
    readonly property int badgeRise: barMargin

    // One size for everything hung under the bar: tooltips, the popups and the
    // tray menus. style.css asked for 1rem, which came out at 14, and at that
    // size a popup read as a paragraph of the bar rather than as a note beside
    // it — and an app's tray menu as a list of sentences.
    readonly property int popupTextSize: 12
    // The launcher's query line: the largest text the shell draws. Spotlight,
    // Alfred and Raycast all make the thing being typed the biggest thing on
    // screen; at the rows' own 12 an open launcher read as a prompt over a
    // list rather than as a question with answers under it.
    readonly property int queryTextSize: 18

    // The escape hatch for the taskbar: a window class does not always resolve
    // to the best icon the theme has. Keyed by window class, and it should stay
    // short. It had a sibling — a per-class pixel trim, carrying one entry for
    // dolphin, whose icon fills its box where its neighbours' do not — which is
    // gone: iconInk measures that now rather than being told it one app at a
    // time.
    readonly property var appIconOverride: ({})

    // --- fonts ---------------------------------------------------------------
    // Inter by default (settings.json): the closest freely licensed thing to
    // SF, and the only font on the bar. Glyphs name the symbol font outright instead of leaning on Qt's
    // fallback, which is unreliable for the private-use codepoints the
    // Material Design icons live in.
    readonly property string bodyFont: Settings.font
    readonly property string glyphFont: "Symbols Nerd Font"
    // A monospace face for the one thing on the shell that is genuinely code:
    // package names and file contents. It used to set every readout too — the
    // calendar, the timers, the song times — because proportional digits make
    // a changing number jitter. Inter carries tabular figures of its own, so
    // those are Inter now (see `figures`), and the shell is one typeface.
    readonly property string monoFont: Settings.monoFont
    // OpenType features every label on the shell is set with. Tabular figures:
    // each digit the same width, so a clock or a countdown holds still as it
    // counts and a column of numbers lines up without a second face.
    readonly property var figures: ({
            "tnum": 1
        })
    readonly property int bodyWeight: Font.Medium // style.css font-weight: 500

    // --- colours -------------------------------------------------------------
    // Text and glyphs, in three of macOS's steps of label: primary for what
    // is read, secondary for what is read after it, tertiary for what is only
    // there. All
    // white at an alpha rather than greys, so they sit on any wallpaper the
    // material lets through. Primary is short of full white on purpose — on
    // a bright wallpaper pure white glares, and 0.85 is where the system
    // draws its own labels.
    readonly property color label: Qt.rgba(1, 1, 1, 0.85)
    readonly property color label2: Qt.rgba(1, 1, 1, 0.55)
    readonly property color label3: Qt.rgba(1, 1, 1, 0.25)
    readonly property color fg: label
    // A pill's fill, and the popups' too: a tooltip or a menu is the bar's own
    // surface carried a little further down, so it is the same half-black
    // rather than the near-opaque grey GTK gave them. The fill has to stay
    // above the 0.3 alpha that wrules.lua's layer rule ignores, or the
    // compositor stops blurring what is behind it — that threshold is also
    // what keeps the gaps between the pills unblurred, so this is the one
    // number both ends depend on.
    readonly property color barBg: Qt.rgba(tint.r, tint.g, tint.b, 0.35)
    // What hangs off the bar — tooltips, popups, menus, the launcher and the
    // power menu — is darker than the bar. The system does the same: its
    // menu bar is barely there over the wallpaper, and its menus are nearly
    // solid, because a menu is read and a bar is glanced at. Same black,
    // so the two still read as one material at two thicknesses.
    readonly property color popupBg: Qt.rgba(tint.r, tint.g, tint.b, 0.65)

    // What "black" means for the two above. It is black until the wallpaper
    // service says otherwise, and then it is the wallpaper's own colour taken
    // down to a near-black of the same hue — the material tinted towards what
    // is behind it, the way vibrancy and Mica are. Set from outside (see
    // services/Wallpaper.qml), which is why it is the one property here that
    // is not readonly.
    property color tint: "black"
    // Every hairline the shell draws: around a pill, around a popup, across a
    // popup between its sections. One colour because they are one thing. White
    // at a whisper rather than a grey — a grey at a tenth on a half-black
    // surface was there in the file and nowhere on the screen.
    readonly property color stroke: Qt.rgba(1, 1, 1, 0.09)

    // The edge of a surface, as opposed to a line across one. A flat hairline
    // at `stroke` vanished over the wallpaper, and over a dark window a popup
    // was a black box on black with nothing to say where it ended. This is
    // glass's answer: a rim lit from above, bright along the top edge and
    // fading to almost nothing by the bottom one. See components/Rim.qml.
    readonly property color rimTop: Qt.rgba(1, 1, 1, 0.2)
    readonly property color rimBottom: Qt.rgba(1, 1, 1, 0.03)

    // The soft shadow under everything that floats over a window: popups, the
    // launcher, the power menu. Not the pills, which sit on the wallpaper
    // rather than over anything. Kept under the 0.2 alpha the compositor's
    // popup blur ignores, so the blur stops at the box and not at the edge of
    // its shadow.
    readonly property color shadow: Qt.rgba(0, 0, 0, 0.18)
    readonly property int shadowBlur: 16
    readonly property int shadowY: 4
    // How much room a popup's window keeps round its box for the shadow to
    // fall into: the blur's reach plus the drop.
    readonly property int shadowPad: shadowBlur + shadowY
    // The row the pointer is on, or the one the keys have reached: a rounded
    // fill inset from the edges of whatever it sits in (selectionInset,
    // selectionRadius), never edge to edge and never with a rule beside it.
    // Lighter than the surface rather than darker, which is which way round
    // macOS does it on a dark material.
    readonly property color selection: Qt.rgba(1, 1, 1, 0.12)

    // A row that is not the selected one carries its text one step down the
    // label scale; the selected one comes up to primary. That is the whole
    // of how a menu says which row it means, beyond the fill under it.
    readonly property color menuText: label2
    readonly property color menuSelectionText: label

    // A dark disc with a white number, the same way round as the rest of the
    // bar. It gets no outline: at 12px an outline costs a pixel of the disc all
    // the way round, which is most of the disc there is.
    readonly property color badgeBg: "#1a1a1a"
    readonly property color badgeFg: "white"

    readonly property color warn: "#ff88aa"

    // The dot at the head of a task row, which is how the list says when
    // something is due without spending a column on saying it. Three steps and
    // no more: a scale finer than "late / now / not yet" is one nobody reads
    // off a four-pixel dot, and the date is written beside it for anything
    // further out than tomorrow.
    //
    // Late reuses the bar's one warm colour rather than introducing a red of
    // its own — there is already exactly one thing on this desktop that means
    // "look at this", and a second one only makes both quieter. Today is the
    // same hue pulled towards amber so the two read as a scale rather than as
    // two unrelated marks, and everything else is the text colour at the
    // opacity a dot needs to be a dot rather than a bullet point.
    readonly property color taskLate: warn
    readonly property color taskToday: "#f0c489"
    readonly property color taskSoon: Qt.rgba(1, 1, 1, 0.45)
    readonly property color taskUndated: Qt.rgba(1, 1, 1, 0.22)

    // The calendar. Today is a filled disc with the numeral cut out of it in
    // the surface colour — the system's own mark, drawn without the system's
    // red so the popup stays one colour like the rest of the bar. Everything
    // else on it is a step of label.
    readonly property color calToday: label
    readonly property color calTodayText: "black"

    // --- opacity -------------------------------------------------------------
    readonly property real idleOpacity: 0.55  // a workspace you are not on
    readonly property real dimOpacity: 0.55   // .stale / .loading
    readonly property int fadeMs: 200         // transition: 0.2s ease-in-out

    // Something folding into or out of a pill (the right pill's drawer), or a
    // pill sliding out from under the clock and back (the timer, the player,
    // the notice — see Bar.qml). Longer than a fade, because this one moves
    // everything beside it across the bar, and a fifth of a second of that
    // read as a jump rather than as a pill growing.
    //
    // Eased in and out, unlike the reveals, which ease out. A reveal is a box
    // arriving and should be there at once; this is a pill's edge travelling
    // a few hundred pixels, and an ease-out puts most of that travel in the
    // first few frames — which, with the icons fading over the same frames,
    // read as the icons going and then the pill snapping shut after them.
    readonly property int foldMs: 360

    // How long the launcher and the power menu take to open out from their
    // centre line, and to fold back into it. Shorter than fadeMs on purpose:
    // this animation is in the way of the thing that was asked for, and a fifth
    // of a second of shutter before the first keystroke can land reads as the
    // launcher being slow to come up rather than as it arriving.
    readonly property int revealMs: 160
    // The launcher's selection sliding from one row to the next. Shorter than
    // the reveal: that one is a box opening and this one is a 28px step, and
    // a step drawn over a tenth of a second is already a long step.
    readonly property int selectMs: 110

    // The attention bounce (components/Bounce.qml). The numbers below are the
    // only ones chosen by hand; every later hop is derived from them, so the
    // bounce obeys one rule rather than a list of tuned offsets.
    //
    // Height the first hop reaches, and the time it spends off the ground.
    readonly property int jumpRise: 7
    readonly property int jumpMs: 280
    // Coefficient of restitution: how much of its height a hop gives back to
    // the next one. Around a third is a tennis ball on concrete — bouncy enough
    // to read as springy, damped enough to settle in three hops rather than
    // drumming. Height falls by this each time; flight time falls by its square
    // root, because time of flight goes with the square root of height.
    readonly property real jumpBounce: 0.33
    // The crouch before the launch. A body that jumps gathers first, and this
    // single pixel of dip is what separates jumping from being flicked upward.
    // It is the one part of this that is animation rather than physics.
    readonly property int jumpCrouch: 1
    readonly property int jumpCrouchMs: 110
    // A click pushes what it lands on down by this much for as long as the
    // button is held. It is the same pixel as the crouch above, gathering under
    // a finger rather than before a jump, and it does not animate: a press is
    // a state, not a motion, and one pixel has nowhere to travel through.
    readonly property int pressDip: jumpCrouch
    // One bounce end to end, landing to landing, rest included. Three seconds
    // because that is the interval the alarm beats at (Timers.beatMs), and the
    // timer's icon is meant to hop on the beat rather than beside it.
    readonly property int jumpPeriodMs: 3000

    // Leaving on a choice, which is not the same event as being dismissed: the
    // box closes onto the row that was picked rather than folding shut about
    // its own middle. The top and bottom edges travel in until the box is that
    // row and nothing else (zipMs), hold there while it is read as the answer
    // (zipHoldMs), then close the rest of the way over it (zipFoldMs). See
    // modules/LauncherMenu.qml.
    //
    // The hold is a beat, not a stop. It has to be long enough to separate the
    // two halves of one motion — without it they run together and the row is
    // never a destination — and short enough that the box is not waiting to be
    // told to go.
    readonly property int zipMs: 140
    readonly property int zipHoldMs: 50
    readonly property int zipFoldMs: 110
    // What the window has to outlive, all three together.
    readonly property int zipTotalMs: zipMs + zipHoldMs + zipFoldMs

    // --- glyphs --------------------------------------------------------------
    // Lifted verbatim from config.jsonc and the scripts it called, by codepoint
    // so nothing is lost to a copy/paste through a non-symbol font.
    // The workspace labels: the alphabet in order, α for the first key on
    // the number row and κ for the tenth. The alphabet rather than the Greek
    // numerals, which would put ϛ at six, and Inter has no ϛ.
    readonly property var workspaceLetters: ["α", "β", "γ", "δ", "ε", "ζ", "η", "θ", "ι", "κ"]

    // A drawing, by file rather than by name, from the copies in icons/ beside
    // this file (its README says where each came from), so the config does not
    // depend on an icon theme having them. Glyph draws any entry below that is
    // one of these in place of the font.
    function panel(name) {
        return "file://" + Quickshell.shellPath("icons/" + name + ".svg");
    }

    readonly property var glyph: ({
        // Drawn after SF Symbols' magnifyingglass rather than nf-md-magnify:
        // that glyph centred on its ink sat the lens a pixel and a half up and
        // left of centre, with the long handle pulling the box the other way.
        // This one's handle is a stub, its viewBox puts it on the pixel grid,
        // and its 1.75px ring stands the weight of the outlined glyphs beside
        // it. launcher-tabler.svg is the thinner one it replaced.
        launcher: panel("launcher"),

        // Every glyph here is Material Design, outlined wherever the set has
        // an outline — the bar and the power menu used to mix in Font Awesome
        // and filled shapes, and read as drawn by several hands.
        //
        // Power menu: WhiteSur's drawings, big enough on the tiles for their
        // hairlines to hold.
        powerShutdown: panel("system-shutdown"),
        powerReboot: panel("system-reboot"),
        powerSuspend: panel("system-suspend"),
        powerLogout: panel("system-log-out"),
        // A crosshair rather than the skull it used to be: the skull was the
        // loudest thing on the strip for the least destructive action on it,
        // and a crosshair is what the action actually puts on screen —
        // hyprctl kill is a click-to-kill cursor (nf-md-crosshairs_gps).
        powerKill: "\u{f01a4}",
        powerConfirm: "\u{f012c}",
        powerCancel: "\u{f0156}",
        // Launcher rows that are not apps: a detected domain, a clipboard
        // entry, and the lock command the power menu deliberately omits.
        web: "\u{f059f}",
        clipboard: "\u{f014c}",
        lock: "\u{f0341}",
        // The / mode's preview panel, for the rows it has no picture to show:
        // a file that is only ever text, and the directories that never will
        // be. See components/FilePreview.qml.
        file: "\u{f0224}",
        folder: "\u{f0256}",

        satty: "\u{f0d5d}",
        wallpaper: "\u{f0e09}",
        window: "\u{f4c3}",           // workspace taskbar fallback

        idleOn: panel("caffeine-cup-full"),
        idleOff: panel("caffeine-cup-empty"),

        nightOn: "\u{f0594}",
        nightOff: "\u{f0599}",         // nf-md-weather_sunny

        cpu: "\u{f0ee0}",
        gpu: "\u{f0fb3}",
        ram: "\u{f035b}",
        disk: "\u{f02ca}",

        update: "\u{f03d7}",
        cleanup: "\u{f00e2}",        // nf-md-broom

        // The tray, for nm-applet. The theme draws wireless as a filled cone
        // with a padlock welded onto it, which at bar size is a blob beside the
        // outlined glyphs every other module carries — so the bar draws its own
        // instead, and the cable in the same hand. See modules/Tray.qml.
        //
        // One outlined cone filling from the bottom, empty to full
        // (nf-md-wifi_strength_outline, then _1 .. _4), so the weak end stays
        // as light as the glyphs beside it. Five of them because nm-applet
        // quantises the signal to five buckets — the bar has the steps it has,
        // not the ones a percentage would suggest. Indexed from zero, so
        // wifiStrength[0] is no signal at all.
        wifiStrength: ["\u{f092f}", "\u{f091f}", "\u{f0922}", "\u{f0925}", "\u{f0928}"],
        // The same cone struck through, outlined rather than filled so that
        // losing the network does not make the icon the loudest thing on the
        // bar (nf-md-wifi_strength_off_outline).
        wifiOff: "\u{f092e}",
        wired: "\u{f0200}",
        wiredOff: "\u{f0202}",

        // The timer module. A countdown and an alarm are the same machine
        // pointed at different things — a span versus an instant — so they are
        // one family of outlined clocks rather than a stopwatch beside a bell.
        // The ringing one is the same face with a mark on it: at bar size a
        // separate "it went off" icon reads as a different module appearing.
        timer: "\u{f051b}",           // nf-md-timer_outline
        timerPaused: "\u{f1adf}",     // nf-md-timer_pause_outline
        timerRing: "\u{f1acd}",       // nf-md-timer_alert_outline
        alarm: "\u{f0020}",           // nf-md-alarm


        // The popups' add button. A bare plus rather than the circled one: it
        // sits at the end of a row the width of a word, and a circle at that
        // size is a ring around two pixels of sign.
        plus: "\u{f0415}",            // nf-md-plus

        // Google Tasks. A checklist for the module, and the two states of one
        // row in its popup: an empty circle to aim at and the same circle with
        // the tick already in it, which is what the pointer sitting on it
        // promises will happen.
        tasks: "\u{f0756}",           // nf-md-format_list_checks
        taskOpen: "\u{f0766}",        // nf-md-circle_outline
        taskDone: "\u{f0134}",        // nf-md-checkbox_marked_circle_outline
        undo: "\u{f054c}",            // nf-md-undo

        // The open mail's two actions in the popup's foot: the thread in the
        // Gmail app, and marking it read, which is the envelope opened.
        openApp: "\u{f03cc}",          // nf-md-open_in_new

        mailRead: "\u{f05ef}",         // nf-md-email_open_outline
        mailUnread: "\u{f01f0}",       // nf-md-email_outline

        // One bell whatever the count: the badge carries the number.
        notif: "\u{f009c}",
        notifDnd: "\u{f0a93}",
        // Do not disturb, in the centre's header: the moon the system uses.
        dnd: "\u{f0904}",            // nf-md-power_sleep
        close: "\u{f0156}",          // nf-md-close

        // One speaker for every output (see services/Audio.qml): the level is
        // its wave count, and muted is the same speaker struck through.
        muted: "\u{f0581}",
        volLow: "\u{f057f}",
        volMed: "\u{f0580}",
        volHigh: "\u{f057e}",
        // No output to play through reads as the same struck-out speaker as
        // muted, not the struck-out note it used to be (nf-md-volume_off).
        audioOff: "\u{f0581}",

        playing: "\u{f040a}",
        paused: "\u{f03e4}",
        // The ones with the bar against them: these move to the track either
        // side rather than running the current one backwards or forwards, and
        // the bar is the difference between the two.
        mediaPrev: "\u{f04ae}",
        mediaNext: "\u{f04ad}",
        // One control cycling off → all → one, so the three states are three
        // glyphs from one family rather than two separate toggles that have to
        // be read together (nf-md-repeat_off, _repeat, _repeat_once).
        repeatOff: "\u{f0457}",
        repeatAll: "\u{f0456}",
        repeatOne: "\u{f0458}",

        // The queue rows' own controls: move this song up or down the queue,
        // and drop it out of it. Filled triangles rather than the chevrons
        // beside them in the font — at the size a queue row gives them, a
        // chevron is two hairlines and reads as lighter than the ✕ it sits
        // next to, while a triangle holds its ink the way the play mark does.
        queueUp: "\u{f0360}",
        queueDown: "\u{f035d}",
        queueRemove: "\u{f0156}",

        // The four kinds of thing in the library the launcher's # mode ranks,
        // so a row says what it is without spending a word on it: a person
        // with a note against them, a record, a note, a list with a note
        // (nf-md-account_music, _album, _music_note, _playlist_music).
        artist: "\u{f0803}",
        album: "\u{f0025}",
        track: "\u{f0387}",
        playlist: "\u{f0cb8}",

        // What can be done to a stored playlist: put it after what is already
        // there, put it on instead, or throw it away. All three are the
        // playlist glyph above with a mark on them, so they read as one family
        // (nf-md-playlist_plus, _playlist_play, _playlist_remove).
        playlistAppend: "\u{f0412}",
        playlistLoad: "\u{f0411}",
        playlistRemove: "\u{f0413}",

        // Which way the popup's playlist section is folded (nf-md-chevron_*).
        sectionOpen: "\u{f0140}",
        sectionShut: "\u{f0142}",

        // The right pill's drawer, which opens to the left: the chevron
        // points the way it will grow, and turns round once it has.
        drawer: "\u{f0141}",         // nf-md-chevron_left
        // The mark on a module pinned out of the drawer (nf-md-pin).
        pin: "\u{f0403}"
    })
}

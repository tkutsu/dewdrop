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
    // More room around the icons. Even, so an icon centres on whole pixels and
    // the pill's round end is exactly half of it. This is the height of a pill
    // rather than of the bar: the layer surface is barInset taller on each
    // side, and the extra is transparent.
    readonly property int barHeight: 30

    // The bar draws nothing itself; its three groups are three separate pills
    // floating on the wallpaper. This is the air off the screen's side edges,
    // and the least that can ever sit between two pills.
    //
    // Keep it equal to Hyprland's general:gaps_out (hypr/configs/*.lua), which
    // is what lines a tiled window's side up with the pill above it.
    readonly property int barMargin: 8

    // The air above the pills and below them: four pixels tighter than the sides.
    // The air below is partly Hyprland's window gap, which is barMargin, so
    // the bar reserves that much less (Bar.reserved).
    readonly property int barInset: 4

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
    // separates two pills' contents on top of the gap between the pills. The
    // radius exactly, so contents start where the curve ends and the straight
    // run begins, the way Apple insets a capsule button's label.
    readonly property int pillPad: pillRadius

    // A popup is a slab hung off a pill rather than a pill itself, so it gets a
    // corner rather than a round end. Three sizes: a popover (the calendar,
    // the sliders, the launcher), a menu (menuRadius below) and a tooltip
    // (tagRadius). The selection inside a popover or a menu is a rounded fill
    // inset from the edge.
    readonly property int popupRadius: 8
    // How far below the slab a popup hangs. The system drops a menu bar's
    // menus flush under the item they came from; this leaves a hairline of
    // wallpaper between the two surfaces so they read as two, and no more.
    // It used to be the whole of barMargin, because the popup hung off the
    // module's box and the box reaches into the margin the pill claims for
    // clicks — which put every menu a click's width away from the click.
    readonly property int popupGap: 2
    readonly property int selectionRadius: 4
    readonly property int selectionInset: 5
    // A menu's corner runs parallel to the highlight inside it: the
    // highlight's radius plus the inset between them, so the two curves share
    // a centre, the way Apple nests its corners. At 5 the box was no rounder
    // than the fill 5px inside it, and the fill's corners looked too round
    // for the box they sat in.
    readonly property int menuRadius: selectionRadius + selectionInset
    // A tooltip's corner. Nothing sits inside a tag for it to run parallel
    // to, and a menu's corner on a box one line high all but makes it a
    // capsule; this is the small corner the Mac gives its help tags.
    readonly property int tagRadius: 5
    // The rounded fill inside a pill that says "this one": the workspace you
    // are on. How far it keeps off the pill's top and bottom edges, and —
    // through pillPad — its ends. Two, the way a segmented control's thumb
    // sits in its track: at three the mark was a chip floating in the pill,
    // and exactly as tall as the app icons it holds.
    readonly property int markInset: 2

    // One gap between things that stand on their own: modules and tray icons.
    // Measured icon to icon — a badge floats in the gap rather than claiming
    // layout width, so a counted module sits exactly as far from its neighbour
    // as an uncounted one does. On the 4pt grid with everything else.
    readonly property int gap: 16

    // Keep workspace groups 2px closer than the gap where their marks meet.
    readonly property int workspaceGap: (pillPad - markInset) * 2 - 2

    // Inside a workspace, its number and window icons sit tighter than that, so
    // the workspace reads as one thing rather than as a run of loose icons.
    // Ink to ink: the icons' boxes follow their artwork and the number is laid
    // out on its ink, so every digit sits as far from its icons as any other.
    readonly property int appIconGap: 4

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

    // The air between neighbouring islands. Apple's spacing between groups of
    // capsules, two thirds of a pill's height: far enough that two pills read
    // as separate islands rather than as one pill with a seam in it, near
    // enough that they still read as neighbours. Content to content, with
    // `pillPad` on either side, it is still over twice `gap`.
    readonly property int pillSpread: 16

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
    // Lit from above, like the rims: what is left of its light along the
    // pill's foot (shaders/track.frag).
    readonly property real pillTrackFoot: 0.3
    // The part still to play, as a trace of the same line, the way Apple's
    // scrubbers keep the rest of the bar in view.
    readonly property real pillTrackRest: 0.2

    // --- type and icon sizes -------------------------------------------------
    // Named rather than scaled off a base size: Symbols Nerd Font only hints
    // cleanly at some pixel sizes — 11 and 13 come out thin and fuzzy, 12 and 14
    // land on the grid — so the 90%/110%/120% spans in config.jsonc are
    // resolved here once instead of rounding into a blurry 13 at each call site.
    //
    // The bar's text is SF, not the symbol font, so none of that applies to
    // it: 13 is the size macOS sets its menu bar in.
    readonly property int textSize: 13
    // The popups' secondary lines — a notification's app and age, the
    // launcher's right-hand hint, a list's rows — one step under their body
    // text (popupTextSize), and moving with it.
    readonly property int captionSize: popupTextSize - 1
    // A step under that again: what is read after the row it belongs to — a
    // row's date, "… and 3 more", the labels on a popup's foot buttons.
    readonly property int footnoteSize: captionSize - 1
    // The / mode's preview of a file's contents, in the mono face: small
    // enough to show a file's shape rather than to be read line by line.
    readonly property int previewTextSize: 9
    // Text that has to hold its own in a row of icons rather than stand alone
    // (the language label, the launcher's rows). A step under textSize, so a
    // label beside an icon doesn't outweigh the icon; kept as its own name
    // because it is a different question from the bar's text.
    readonly property int labelSize: 12
    // Use the icon artwork's target size for the language label's font size.
    readonly property int languageTextSize: 13
    // The workspace numbers: a step under the clock, so they read as marks
    // on the taskbar rather than as words beside its icons.
    // A 16px font gives roughly 13px of visible icon artwork; individual
    // shapes keep the proportions drawn into the font.
    readonly property int glyphSize: 16
    // Glyphs inside a popup, beside its 12px text rather than the bar's.
    readonly property int popupGlyphSize: 14
    readonly property int glyphSizeLarge: 16
    // Network, Bluetooth and tray stand-ins use the same icon font size.
    readonly property int trayGlyphSize: 16
    // One size for everything the bar draws from artwork rather than from a
    // font — the tray and the workspace taskbar. The 20px ceiling leaves room
    // for artwork with built-in margins to reach the 13px visible target.
    //
    // It used to be two, 16 here and 13 for the taskbar, because the two sets
    // are drawn to different conventions: a panel icon keeps margin inside its
    // box, an application icon fills it edge to edge, and the same box gave
    // them visibly different ink. The box is not what decides that any more
    // (see iconInk), so the convention the artwork was drawn to stopped
    // mattering and the second size went with it.
    readonly property int iconSize: 20
    // How tall an icon's ink should stand in its box, measured rather than
    // assumed (components/InkProbe.qml). Thirteen pixels of ink in a 20px box
    // keeps tray and workspace artwork on the same line despite different
    // margins in the source images.
    readonly property real iconInk: 13 / 20
    // Drawings in glyph slots share the artwork's visible target (see Glyph).
    readonly property real glyphInk: 13 / 20

    // The count badge on a module's glyph (BadgedGlyph): unread mail, updates.
    readonly property int badgeSize: 13
    // 10 rather than 9: at 9 a figure's ink came out half a pixel right of
    // the disc's middle (a 3 by 0.4px), at 10 it lands within a fifth of one.
    readonly property int badgeTextSize: 10
    // Where every badge's centre line sits, measured from the top of the pill
    // (see pillTop), so badges line up across the bar whatever size the icon
    // beneath them is.
    readonly property int badgeLine: 8

    // The dot under the taskbar icon holding the focused window, the way the
    // Dock marks a running app: small enough to read as a mark rather than a
    // shape, and hung on a line of its own from the top of the pill, below
    // the icons' ink and inside the workspace mark.
    readonly property int focusDotSize: 3
    readonly property real focusDotLine: 22.5
    // The gap cut out of the icon's artwork round the dot, so the two never
    // touch.
    readonly property real focusDotClearance: 1.5

    // The pin mark on a pinned module's lower right corner, shown while the
    // drawer is open: the count badge's disc, with a pin in place of the
    // number.
    readonly property int pinMarkSize: badgeSize
    readonly property int pinGlyphSize: 9

    // Every count on the bar rides the top edge of the pill instead of sitting
    // inside it: half on the slab, half on the margin above, which gives the
    // icon underneath its corner back. Its own number rather than barInset,
    // so widening the air around the bar leaves the badges where they sit;
    // barInset is still the ceiling, since any higher and the badge is drawn
    // outside the layer surface and loses its top.
    readonly property int badgeRise: 4

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

    // Leave enough contrast at rest for a visible lift towards each ink's white.
    function barInk(item, color) {
        for (let p = item; p; p = p.parent) {
            if (p.inkHovered === undefined)
                continue;
            if (!p.inkHovered)
                return Qt.rgba(color.r, color.g, color.b, color.a * 0.8);
            if (color.a === 0)
                return color;
            return Qt.rgba(color.r + (1 - color.r) * 0.65,
                color.g + (1 - color.g) * 0.65,
                color.b + (1 - color.b) * 0.65,
                color.a + (1 - color.a) * 0.8);
        }
        return color;
    }
    // A pill's fill: half black, and what the clear glass lays over the
    // wallpaper it draws (glassTint), rather than the near-opaque grey GTK
    // gave the bar. popupBg below is the popups' own. The fill has to stay
    // above the 0.3 alpha that wrules.lua's layer rule ignores, or the
    // compositor stops blurring what is behind it — that threshold is also
    // what keeps the gaps between the pills unblurred, so this is the one
    // number both ends depend on.
    readonly property color barBg: Qt.rgba(tint.r, tint.g, tint.b, 0.35)
    // What hangs off the bar — tooltips, popups, menus, the launcher and the
    // power menu — is frosted glass rather than the bar's clear glass: a thin
    // fill at little more than the 0.3 the blur rule ignores, so most of what
    // it shows is Hyprland's heavy blur, and a bright patch behind it comes
    // through as a glow. The blur is what keeps a window's text from showing
    // through, not the fill.
    //
    // Dark enough that it holds about level over a dark window and pulls
    // anything bright down, so the white labels on it keep their contrast
    // whatever it opens over. Half the tint's saturation, so it reads as frost
    // with a cast of the wallpaper rather than as a coloured sheet.
    readonly property color popupBg: Qt.hsla(Math.max(0, tint.hslHue), tint.hslSaturation / 2, 0.12, 0.36)

    // popupBg over something bright, for a box that knows what it is opening
    // over (components/BackdropProbe.qml), and popupBg itself for one that
    // does not know yet (-1). Over white, 0.36 of a dark fill
    // comes out a light grey, and `label` on that is white on grey. The fill
    // is thickened until what shows through lands at frostCeiling, where
    // `label` holds about 6.5:1 and `label2` about 4:1; behind anything at or
    // under that it is popupBg exactly, so a dark window gets the same glass
    // as ever. Never past 0.85, so it stays frost and never goes solid.
    readonly property real frostCeiling: 0.3
    function frostOver(luma) {
        const c = popupBg;
        const own = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        if (luma <= frostCeiling)
            return c;
        const a = (luma - frostCeiling) / (luma - own);
        return Qt.rgba(c.r, c.g, c.b, Math.min(0.85, Math.max(c.a, a)));
    }

    // What "black" means for the two above. It is black until the wallpaper
    // service says otherwise, and then it is the wallpaper's own colour taken
    // down to a near-black of the same hue — the material tinted towards what
    // is behind it, the way vibrancy and Mica are. Set from outside (see
    // services/Wallpaper.qml), which is why it is the one property here that
    // is not readonly.
    property color tint: "black"
    // What the pills are laid over, as one colour: the wallpaper's average,
    // from the same place and for the same reason as tint.
    property color backdrop: "black"
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
    // A touch under the popups' rim: a pill sits on the wallpaper rather than
    // over a window, and needs less edge to read as one.
    readonly property color pillRimTop: Qt.rgba(1, 1, 1, 0.15)

    // The clock's glass over an image wallpaper: clear rather than frosted,
    // drawing the wallpaper itself (Liquid.backdrop, shaders/liquid.frag).
    // Near the edge it looks glassBend pixels further in, easing off to
    // nothing by glassBendDepth, the way the rim of a lens pulls what is under
    // it towards the middle. Red bends glassDispersion less than that and
    // blue as much more, so the edge fringes with colour. A touch of blur and
    // a lift in colour, then barBg's near-black laid over it at glassTint so
    // labels still read. glassBendDepth is half the pill: any deeper and the
    // bends from the top and bottom edges would meet in the middle in a seam.
    readonly property real glassBend: 7
    readonly property real glassBendDepth: 12
    readonly property real glassDispersion: 0.2
    readonly property real glassSoften: 1.5
    readonly property real glassSaturation: 1.5
    readonly property real glassTint: 0.3

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
    // One step past it: a toggle that is on, or the pointer on a button that
    // already sits on a selection fill (the notification centre's).
    readonly property color selectionStrong: Qt.rgba(1, 1, 1, 0.2)
    // The workspace mark while a press is held on the strip: the glass lifts
    // towards the pointer, and a lifted piece of glass catches more light.
    readonly property color markLifted: Qt.rgba(1, 1, 1, 0.28)
    // The mark's own edge. It is glass laid on the pill's glass, and without
    // a rim of its own it read as a stain in the pill rather than a piece on
    // it. A step brighter along the top than the pill's rim, so the two lines
    // read as two surfaces rather than one line drawn twice.
    readonly property color markRimTop: Qt.rgba(1, 1, 1, 0.25)

    // The way from one colour to another, `t` of it along.
    function mix(from, to, t) {
        return Qt.rgba(from.r + (to.r - from.r) * t, from.g + (to.g - from.g) * t, from.b + (to.b - from.b) * t, from.a + (to.a - from.a) * t);
    }

    // Outlines round a thing you can pick — the wallpaper popup's thumbnails
    // and swatch: none, or `outline`, at rest, `outlineHover` under the
    // pointer, and `fg` once it is the one on screen.
    readonly property color outline: Qt.rgba(1, 1, 1, 0.3)
    readonly property color outlineHover: Qt.rgba(1, 1, 1, 0.5)

    // The empty frame a picture is drawn into, there whether or not the
    // picture is: album art, a folder's cover.
    readonly property color well: Qt.rgba(1, 1, 1, 0.06)
    // The dark fade laid over the foot of a picture so controls read on it.
    readonly property color scrim: Qt.rgba(0, 0, 0, 0.72)

    // The empty part of a readout bar (the system popup's meters and cores),
    // quiet enough that an empty one is not a bright line, and of a slider,
    // which is a control and a step brighter.
    readonly property color meterTrack: Qt.rgba(1, 1, 1, 0.12)
    readonly property color sliderTrack: Qt.rgba(1, 1, 1, 0.2)
    // A slider's knob is `fg` with a dark edge. On a gradient track it crosses
    // white, yellow and black, so there the edge is darker still.
    readonly property color knobEdge: Qt.rgba(0, 0, 0, 0.35)
    readonly property color markerEdge: Qt.rgba(0, 0, 0, 0.7)

    // A handle on other things rather than a thing (the drawer's chevron):
    // fainter than the glyphs it opens onto, so it does not read as a status.
    readonly property color handle: Qt.rgba(1, 1, 1, 0.4)

    // A row that is not the selected one carries its text one step down the
    // label scale; the selected one comes up to primary. That is the whole
    // of how a menu says which row it means, beyond the fill under it.
    readonly property color menuText: label2
    readonly property color menuSelectionText: label

    // The workspace mark's glass, made solid: the mark's white laid over the
    // pill laid over the wallpaper, worked out here rather than left to the
    // compositor. The badge sits over an icon's strokes, and glass would let
    // them up under the number or the pin. It takes the mark's rim as well.
    // A count badge samples the wallpaper under its icon's area. Pin marks
    // keep the pill's surface; outside a pill, use the wallpaper's average.
    function badgeBg(item, area) {
        let ground = mix(backdrop, tint, barBg.a);
        let x = area?.x ?? 0, y = area?.y ?? 0;
        for (let p = item; p; p = p.parent) {
            // Read the layout positions and BarItem's spring translation:
            // mapToItem alone would not make these binding dependencies.
            if (area) {
                x += p.x + (p.shift ?? 0);
                y += p.y;
            }
            if (p.surface !== undefined) {
                ground = area && p.backdrop?.columns?.length
                    ? glassOver(p.backdrop.averageRegion(Qt.rect(x - p.backdrop.x, y - p.backdrop.y, area.width, area.height)))
                    : p.surface;
                break;
            }
        }
        return mix(ground, Qt.rgba(1, 1, 1, 1), selectionStrong.a);
    }

    // What the clear glass makes of a colour behind it, the way liquid.frag
    // does it: saturation raised by glassSaturation, then the tint laid over
    // at glassTint.
    function glassOver(c) {
        const luma = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        const lift = v => Math.min(1, Math.max(0, luma + (v - luma) * glassSaturation));
        return mix(Qt.rgba(lift(c.r), lift(c.g), lift(c.b), 1), tint, glassTint);
    }
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
    readonly property real dimOpacity: 0.55   // .stale / .loading
    readonly property int fadeMs: 200         // transition: 0.2s ease-in-out

    // The workspace mark flowing from one workspace to the next: its back end
    // lets go a fifth of the way into this and is drawn in over the rest,
    // behind a front end that runs on a spring (markDamping).
    readonly property int markMs: 420
    // That spring: springStiffness with SwiftUI's plain .bouncy damping,
    // which arrives in about 250 ms — when the front end used to — and
    // overshoots 4.7% before it settles (measured, 2026-09-29). Not the music
    // pill's extra bounce: the overshoot is a share of the distance run, and
    // at 16% a jump across the strip would carry the mark most of a
    // workspace past the one it is going to.
    readonly property real markDamping: 0.26
    // The mark running into an end of the pill: how far past the wall the
    // spring has to carry it to press it flat, and how much taller the glass
    // piled against the wall stands, each side, once it is. Held to what
    // keeps that bulb inside the pill's round end, rim and all.
    readonly property real markPress: 6
    readonly property real markBulge: 1.5

    // The workspaces you are not on, a little under the one you are: their
    // letters and icons, not their counts, so a number stays as legible as
    // it was.
    readonly property real restOpacity: 0.75

    // Something folding into or out of place in a popup or a pill: a message
    // in the mail popup, the music pill's parts. Longer than a fade, because
    // it moves what is beside it, and a fifth of a second of that read as a
    // jump rather than as a thing growing.
    //
    // Eased in and out, unlike the reveals, which ease out. A reveal is a box
    // arriving and should be there at once; this is an edge travelling, and
    // an ease-out puts most of that travel in the first few frames — which,
    // with the contents fading over the same frames, read as them going and
    // then the box snapping shut after them.
    readonly property int foldMs: 360

    // The side pills use the music title's spring (Music.qml): the same
    // stiffness and damping for workspace width changes.
    readonly property real foldSpring: springStiffness
    readonly property real foldDamping: 0.14
    // The drawer folds on a softer one: a 12% overshoot rather than 30%.
    // Drawer modules land first, then the glass settles (Pill.stretch).
    // At 2.2 / 0.20, Qt's spring first reaches its target at about 208 ms.
    readonly property real drawerSpring: 2.2
    readonly property real drawerDamping: 0.20
    readonly property int foldLandMs: 208
    // Before the drawer folds, the glass winds up the other way by this
    // much, in pixels, and lets go into the spring (Drawer.windup): drawn in
    // past shut before opening, out before shutting. Small beside the
    // twenty-odd pixels the spring runs past by, and quick, so it reads as
    // the glass loading up rather than as a false start.
    readonly property real windup: 5
    readonly property int windupMs: 110
    // How long after the bar starts the drawer folds without the spring
    // (BarItem): long enough for its modules' services to answer, which
    // took under a second for the update checks (measured, 2026-09-30).
    readonly property int startMs: 2000

    // The drawer's chevron turning over once the fold has come to rest: a
    // half turn of a few pixels of ink, which wants to be quick to read as the
    // handle answering rather than as a second thing moving.
    readonly property int turnMs: 240

    // A pill beside the clock being drawn into its neighbour, or coming back
    // out (Bar.drop). Longer than a fold: it is three moves in a row, the
    // contents going, the pill rounding up and the drop travelling in, and
    // each of them needs time enough to read as a move of its own.
    readonly property int dropMs: 620

    // Stiffness shared by the pill and selection springs; each uses its own damping.
    readonly property real springStiffness: 2.5

    // Figures rolling to their next value (RollingText): SwiftUI's default
    // duration, which the roll runs 1.45 times over while its spring settles
    // — 725 ms, inside the second before the timer's next figure.
    readonly property int rollMs: 500

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
    // Each beat of a menu row's blink when it is chosen: out for this long,
    // back for this long, then the menu acts (components/MenuPopup.qml).
    readonly property int blinkMs: 60

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

    // A drawing, by file rather than by name, from the copies in icons/ beside
    // this file (its README says where each came from), so the config does not
    // depend on an icon theme having them. Glyph draws any entry below that is
    // one of these in place of the font.
    function panel(name) {
        return "file://" + Quickshell.shellPath("icons/" + name + ".svg");
    }

    // A drawing cut out of the icon font itself, in the font's em box: Glyph
    // draws it at the font size rather than at a drawing's, so it stands
    // exactly as big as the glyph it came from.
    function fontCut(name) {
        return panel(name) + "#em";
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
        // Power menu: WhiteSur's drawings, big enough on the discs for their
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

        nightOn: "\u{f0336}",         // nf-md-lightbulb_outline (dim)
        nightOff: "\u{f06e8}",        // nf-md-lightbulb_on_outline (lit)

        cpu: "\u{f0ee0}",
        gpu: "\u{f0fb3}",
        ram: "\u{f035b}",
        disk: "\u{f02ca}",

        update: "\u{f03d7}",
        refresh: "\u{f0450}",        // nf-md-refresh
        cleanup: "\u{f00e2}",        // nf-md-broom

        // The network module (it began as the tray's stand-in for nm-applet,
        // whose theme art is a filled cone with a padlock welded onto it, a
        // blob beside the outlined glyphs every other module carries). The
        // cable is in the same hand. See services/Network.qml.
        //
        // Drawn after SF Symbols' wifi: a dot and three thin arcs about it,
        // lit from the dot up with the rest left faint, the way the volume
        // speaker's waves fade in, so every step stands the same size. The
        // font's cone it replaces filled solid as the signal rose. Five
        // because nm-applet quantised the signal to five buckets, and
        // Network.bars still does — the bar has the steps it has, not the ones
        // a percentage would suggest. Indexed from zero, so wifiStrength[0] is
        // no signal at all.
        wifiStrength: [0, 1, 2, 3, 4].map(n => panel("network-wireless-" + n)),
        // The faint arcs struck through, so losing the network does not make
        // the icon the loudest thing on the bar.
        wifiOff: panel("network-wireless-off"),
        wired: "\u{f0200}",
        wiredOff: "\u{f0202}",
        // Mullvad, whose own icon is a solid padlock filling its box with a
        // status dot on it. The same outlined hand as the cone: shut while the
        // tunnel is up, the shackle swung open otherwise (nf-md-lock_outline,
        // nf-md-lock_open_variant_outline).
        vpn: "\u{f0341}",
        vpnOff: "\u{f0fc7}",
        // The Bluetooth module, in place of blueman's theme drawing: a thin
        // rune in the theme's own blue, narrow enough to read a size down once
        // scaled to the row. On or off only, struck through like the cone
        // (nf-md-bluetooth, nf-md-bluetooth_off).
        bluetooth: "\u{f00af}",
        bluetoothOff: "\u{f00b2}",
        // The drives module: a simple USB symbol and an outlined eject
        // for safe removal (nf-md-usb, nf-md-eject_outline).
        drive: "\u{f0553}",
        eject: "\u{f0b91}",

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
        // A starred mail in the launcher's search, which is why it is on top.
        mailStarred: "\u{f04d2}",      // nf-md-star_outline

        // One bell whatever the count: the badge carries the number.
        notif: "\u{f009c}",
        notifDnd: "\u{f0a93}",
        // Do not disturb, in the centre's header: the moon the system uses.
        dnd: "\u{f0904}",            // nf-md-power_sleep
        close: "\u{f0156}",          // nf-md-close
        check: "\u{f012c}",          // nf-md-check, the one in use in a list

        // One speaker for every output (see services/Audio.qml), drawn from
        // nf-md-volume_high so each wave can take its own opacity, the way
        // the caffeine cup's steam does: empty is both waves at .25, then the
        // inner one comes up through .5 and .75 to full, then the outer one.
        // Muted is nf-md-volume_off, drawn the same way.
        muted: fontCut("audio-volume-muted"),
        vol: [0, 1, 2, 3, 4, 5, 6].map(n => fontCut("audio-volume-" + n)),
        // No output to play through reads as the same struck-out speaker as
        // muted, not the struck-out note it used to be (nf-md-volume_off).
        audioOff: fontCut("audio-volume-muted"),
        // The input's row in the sound popup, and its mute.
        mic: "\u{f036e}",            // nf-md-microphone_outline
        micMuted: "\u{f036d}",       // nf-md-microphone_off

        playing: "\u{f040a}",
        paused: "\u{f03e4}",
        stopped: "\u{f04db}",
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

        // The mark on a module pinned out of the drawer (nf-md-pin). The
        // drawer's own chevron is drawn rather than a glyph (Drawer.qml).
        pin: "\u{f0403}",

        // The settings window: its own module, and the right pill's rows for
        // the modules that draw something other than one fixed glyph.
        settings: "\u{f425}",         // nf-oct-tools
        keyboard: "\u{f097b}",       // nf-md-keyboard_outline
        tray: "\u{f1294}",           // nf-md-tray
        gauge: "\u{f029a}"           // nf-md-gauge
    })
}

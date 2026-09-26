import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs
import qs.components
import qs.services

// The launcher box: a query line over a list of matches.
//
// Laid out the way ~/.config/rofi/theme.rasi laid rofi out, because that is
// what the desktop has looked like for years — a narrow half-black box, one
// lowercase name per row, its icon out at the right edge, and the row you are
// on marked by a grey fill with a white rule down its left side.
//
// The screen-sized surface under it, the keyboard grab and the click-to-exit
// are OverlayWindow's, which the power menu is drawn on too. That surface is
// the part rofi could not do for itself — see services/Launcher.qml.
OverlayWindow {
    id: root

    name: "launcher"
    shown: Launcher.shown
    onDismissed: Launcher.hide()

    // --- the reveal ----------------------------------------------------------
    // How far open the box is, 0 to 1. This is what animates, rather than the
    // box's height directly, because the height is also what the list changes
    // on every keystroke: a Behavior on the height cannot tell the reveal from
    // a result arriving, so it animates both and the box bounces under each
    // letter typed. Here the two are separate things — the reveal is this
    // number moving, and the list resizing the box is not a reveal at all.
    property real reveal: root.opened ? 1 : 0

    Behavior on reveal {
        NumberAnimation {
            duration: Theme.revealMs
            easing.type: Easing.OutCubic
        }
    }

    // --- the exit ------------------------------------------------------------
    // Being dismissed folds the box shut about its own middle, which is the
    // reveal run backwards and is what `reveal` above already does. Being used
    // is a different event and gets a different exit: the box closes onto the
    // row that was picked. Its top edge falls and its bottom edge climbs until
    // the two of them wrap that row and nothing else, they hold there long
    // enough for it to be read as the answer, and then they close over it too.
    //
    // Nothing moves but the edges. The contents hold their place on screen and
    // are covered rather than pushed, which is the same trick the reveal uses:
    // a list that slid out from under its own box would read as the box being
    // crushed rather than as a choice being taken.
    //
    // Deliberately no fade, for the reason given further down: the box's alpha
    // is only just over the floor the compositor's blur rule ignores, and
    // anything that takes it down drops the blur out partway through.
    //
    // The second motion carries on rather than turning the corner: the same two
    // edges that stopped on the row close the rest of the way into it. It used
    // to fold the row in from its two ends instead, and a box that had spent
    // its whole exit travelling one way and then finished sideways read as two
    // animations that happened to be next to each other. The hold between them
    // is what lets one motion stop and start again without becoming two: with
    // no pause at all the edges never arrive anywhere, and the row they close
    // on is a frame they pass through rather than the answer they picked.
    //
    // `zip` is the first, 1 at the full box and 0 at one row; `fold` is the
    // second, 1 at that row's full height and 0 at none. Both sit at 1 for as
    // long as the box is open, so a box leaving any other way never feels them.
    property real zip: 1
    property real fold: 1
    // Where the chosen row was, as an offset from the top of the box, taken
    // once at the moment of the choice: everything below is built on this one
    // number and the list it came from is about to be taken apart.
    property real focus: 0
    property bool zipping: false

    // The row's top in the box's own coordinates. Asked of the item rather
    // than worked out from the index, because a list that has been scrolled
    // has no fixed relation between the two — with the arithmetic kept as the
    // answer for a row too far off-screen to have been built, and the whole
    // thing held inside the box so that a mode with no list at all still
    // closes on a line that is part of the box.
    function rowTop(i) {
        const item = list.itemAtIndex(i);
        const y = item ? item.mapToItem(box, 0, 0).y : content.y + list.y + i * root.rowHeight - list.contentY;
        return Math.max(0, Math.min(box.bodyHeight - root.rowHeight, y));
    }

    Connections {
        target: Launcher

        function onShownChanged() {
            if (Launcher.shown) {
                // A window reused inside its own fold-away (see qs.Linger)
                // would otherwise open with the last exit still applied to it.
                root.zipping = false;
                root.zip = 1;
                root.fold = 1;
                exit.stop();
                // And with the two bindings the exit broke on purpose still
                // broken: a reused window would hold the height and the rows
                // of the box that just left, so the list would be frozen on
                // the last search and would not resize for this one. Put back
                // rather than assigned, because what they were is a binding.
                box.bodyHeight = Qt.binding(() => box.restHeight);
                list.model = Qt.binding(() => Launcher.results);
                // The field too: Launcher.query was reset behind it, and a
                // reused window would still be showing the last search while
                // listing the new one.
                input.adopt(Launcher.query);
                // And the pointer starts dead again, or opening under a
                // stationary cursor would steal row 0 (see the rows' MouseArea).
                list.pointerLive = false;
                return;
            }
            // Dismissed rather than used: the reveal has it.
            if (Launcher.chosen < 0)
                return;
            root.focus = root.rowTop(Launcher.chosen);
            // Assigned rather than left bound, which breaks the binding on
            // purpose: activating a row can change what the list would rank
            // (launching an app bumps its frecency), and a body that resized
            // itself halfway through the exit would drag both edges with it.
            // The box is leaving; what it would have measured no longer
            // matters.
            box.bodyHeight = box.restHeight;
            // And the rows themselves, for the same reason and in the same
            // way: launching an app bumps its frecency, which re-ranks the
            // list it was chosen from. The list you picked from is the one
            // that should be on screen while the box closes over it.
            list.model = Launcher.results.slice();
            root.zipping = true;
            exit.start();
        }
    }

    SequentialAnimation {
        id: exit

        NumberAnimation {
            target: root
            property: "zip"
            from: 1
            to: 0
            duration: Theme.zipMs
            easing.type: Easing.OutCubic
        }
        PauseAnimation {
            duration: Theme.zipHoldMs
        }
        NumberAnimation {
            target: root
            property: "fold"
            from: 1
            to: 0
            duration: Theme.zipFoldMs
            easing.type: Easing.InCubic
        }
    }

    // --- geometry ------------------------------------------------------------
    // What Spotlight is. Apple publishes no figure for it, so this is a
    // measurement of Apple's own Big Sur screenshot: 680 of window body, over
    // a result row pitch of 28 — which is the height this list already drew
    // at, arrived at separately. The rest of the field agrees to within a
    // fifth. Alfred's default theme is 560 and its Modern one 700, Raycast is
    // a documented 750, and Sol, which exists to be a native Spotlight, is 700.
    //
    // It was 360 before, inherited from rofi's 15em at Ubuntu Light 10. That
    // was too narrow for the box to say what it could do: the engine line
    // under the query wants 447 and was being elided at the seventh of nine.
    // Everything below is derived, so this is still the only number to turn.
    readonly property int boxWidth: 680
    readonly property int rowHeight: 28
    // rofi drew 9; 12 is as deep as the list goes before it stops being a
    // glance and starts being a scroll. maxResults still ranks well past this,
    // so the rest is reachable by arrowing down.
    readonly property int visibleRows: 12
    readonly property int boxPad: 12
    // The right-hand slot every row ends in: an app icon, or the "@yt" badge
    // that says which engine Enter would use.
    readonly property int slotWidth: 24
    // How far a row is set in per level of the music mode's tree. Wide enough
    // to be read as a step rather than a misalignment, narrow enough that a
    // track two levels down still has most of the line for its title.
    readonly property int indentStep: 16
    // The query line, and the air above and below its rule.
    readonly property int inputHeight: Theme.queryTextSize + 12
    readonly property int contentGap: 8
    // The preview panel / mode grows on the right, and the air between it and
    // the list. Roughly a third of the body, which is about what Spotlight
    // gives its own preview, set in the same 12 of air as everything else in
    // the box. See components/FilePreview.qml.
    readonly property int panelWidth: 220
    readonly property int panelGap: boxPad

    // Whether the box is showing one. Bound to the mode rather than to the
    // selected row having a picture in it: a panel that came and went as the
    // selection moved between a photograph and a text file would resize the
    // box under every arrow key. Music mode holds it open for exactly the same
    // reason — a playlist row has no sleeve, and the box must not shut by 232
    // pixels because you arrowed past one.
    readonly property bool previewing: Launcher.pathMode || Launcher.musicMode

    // The box at its tallest, with the list full. This places the box; it does
    // not size it. The top edge is pinned where a full box would have been
    // centred, so a launcher showing twelve rows sits exactly where the centred
    // one used to, and every shorter one keeps its query line on that same line.
    readonly property int fullHeight: boxPad * 2 + inputHeight + contentGap * 2 + Theme.pillBorder + visibleRows * rowHeight

    // Move the answer instead of the selection, when there is an answer too
    // long to sit in the box and only the one row that asked for it. Returns
    // whether it took the key.
    function scroll(dir) {
        if (!answer.visible || answer.contentHeight <= answer.height)
            return false;
        answer.contentY = Math.max(0, Math.min(answer.contentHeight - answer.height, answer.contentY + dir * root.rowHeight * 2));
        return true;
    }

    // Tab in music mode, which rebuilds a list that is not supposed to move.
    // The model is a plain array and replacing one empties the view before it
    // refills it: the count drops to nothing, contentY drops with it, and the
    // list comes back at the top however far down it had been scrolled. The
    // selection is restored by then, so what is seen is a list that jumped to
    // the top of the library and a highlight flying back down to where it
    // already was.
    //
    // So the scroll is taken before the fold and put back after it. Opening
    // only adds rows below the selection and shutting in place only takes
    // them away, and neither is a reason for anything on screen to move.
    // Shutting from inside a record is the one case that has to: the row it
    // goes back up to can be off the top edge by then, and is brought in no
    // further than it has to come.
    function foldTree() {
        const was = list.contentY;
        Launcher.fold();
        // Otherwise the rows are made on the next polish and contentHeight,
        // which the scroll is clamped against, is still the old list's.
        list.forceLayout();
        const max = Math.max(0, list.contentHeight - list.height);
        list.contentY = Math.max(0, Math.min(max, was));
        root.reveal();
    }

    // Keeping the selected row on screen, and scrolling no further than it
    // takes to get it there. The view used to do this for itself, off the
    // current item it was tracking — it does not any more, because the
    // highlight below is placed rather than followed, and a view left with
    // nothing to track will happily let the selection walk off the bottom
    // edge. So the rule it had is written out: never above the top edge,
    // never below the bottom one, and otherwise wherever the list already is.
    function reveal() {
        const top = Launcher.index * root.rowHeight;
        const floor = top + root.rowHeight - list.height;
        const max = Math.max(0, list.contentHeight - list.height);
        const y = Math.max(0, Math.min(max, Math.max(floor, Math.min(top, list.contentY))));
        scrollTo.stop();
        if (y !== list.contentY) {
            scrollTo.to = y;
            scrollTo.start();
        }
    }

    // On its own rather than a Behavior on contentY: that property is also
    // what a flick writes to, frame by frame, and an animation sitting on it
    // would be fighting the pointer for the list.
    NumberAnimation {
        id: scrollTo

        target: list
        property: "contentY"
        duration: Theme.selectMs
        easing.type: Easing.OutCubic
    }

    // The box's shadow, as a sibling rather than a child: the box clips its
    // children to itself, and a shadow is everything outside the box.
    RectangularShadow {
        x: box.x
        y: box.y
        width: box.width
        height: box.height
        visible: box.height > 0
        offset.y: Theme.shadowY
        radius: box.radius
        blur: Theme.shadowBlur
        color: Theme.shadow
    }

    Rectangle {
        id: box

        // What the box would be if it were open and settled: exactly its
        // contents. Instant, so it is a measurement rather than a motion.
        //
        // With a panel open there is a floor under that: a two-row list would
        // otherwise leave the preview a 220x30 slot to put a photograph in,
        // and a square is the least a picture can be shown in and still be
        // one.
        readonly property int restHeight: Math.max(content.implicitHeight, root.previewing ? root.panelWidth : 0) + root.boxPad * 2

        // And what it is actually drawn at, trailing that measurement: the list
        // gaining a row pushes the bottom edge down to it rather than landing
        // there, so the box reads as a drawer the results are filling. It is a
        // second animated value and not the reveal's, because the two are
        // different motions — this one is the list changing length, and a
        // Behavior on the height itself could not tell them apart.
        property real bodyHeight: box.restHeight

        Behavior on bodyHeight {
            NumberAnimation {
                duration: Theme.revealMs
                easing.type: Easing.OutCubic
            }
        }

        // Hung from a fixed line rather than centred. Centring re-places the box
        // every time the list changes length, which walks the query line up the
        // screen as results arrive and back down as they are filtered away — so
        // the one thing being looked at while typing is the one thing that will
        // not hold still. Pinned, the list grows and shrinks downwards under a
        // query line that never moves.
        //
        // The Column inside stays centred (see below): the box is sized to fit
        // its contents exactly, so centring them in it puts the query line
        // boxPad below this edge and leaves it there.
        //
        // How far each edge has come in from where a settled box would have
        // had it, which is the one place the two ways of closing differ.
        //
        // Opening and being dismissed, both are the reveal and nothing else:
        // half the height the box has yet to gain, off each end, which puts a
        // closed box on the centre line of where it is about to be and walks
        // its edges out to the settled ones as it opens. Open, `reveal` is 1
        // and both terms are zero, so the top is the pinned line exactly and a
        // list that grows can only grow downwards — the reveal borrows the
        // box's position and gives it back.
        //
        // Leaving on a choice, they are the zip and then the fold: the top edge
        // falls by everything above the chosen row and the bottom edge climbs
        // by everything below it, they hold there, and then the fold takes the
        // half-row each still has between it and the row's own middle. Both
        // terms are on both edges and the second is zero until the first has
        // finished, so the pair reads as one travel with a beat in it.
        // Rounded here and nowhere else. The contents are held in place by
        // being moved against these — up by as much as the top edge comes
        // down — and two Math.rounds of the same fractional number, one for
        // the box and one for what is inside it, disagree by a pixel every
        // time the rounding falls either side of a half. That pixel appears
        // and disappears as the animation runs, which reads as the whole list
        // jittering up and down inside a box that is moving smoothly.
        readonly property int topEdge: Math.round(root.zipping ? root.focus * (1 - root.zip) + root.rowHeight * (1 - root.fold) / 2 : box.bodyHeight * (1 - root.reveal) / 2)
        readonly property int bottomEdge: Math.round(root.zipping ? box.bodyHeight - (box.bodyHeight - root.focus - root.rowHeight) * (1 - root.zip) - root.rowHeight * (1 - root.fold) / 2 : box.bodyHeight - box.bodyHeight * (1 - root.reveal) / 2)

        y: Math.round((root.height - root.fullHeight) / 2) + box.topEdge
        // Placed rather than centred, for the same reason the y is placed
        // rather than centred. In / mode the box grows a preview panel on its
        // right, and a centred box would answer that by walking the query
        // line and every row in the list left to make room for it. Pinned
        // where a 680-wide box's left edge was, the panel opens out into the
        // screen instead and nothing already drawn moves at all.
        // What the box is across: the list, and the panel when / mode has one.
        // Nothing in the exit touches it any more — both of that animation's
        // motions belong to the top and bottom edges — so opening the panel is
        // the only thing the width ever does.
        //
        // Still animated a step away from `width` rather than on it, so the
        // drawn width can be a whole number while the animation runs through
        // the fractions between two of them. A box on a half pixel puts its
        // rule, its rows and its icons there too.
        property real bodyWidth: root.boxWidth + (root.previewing ? root.panelGap + root.panelWidth : 0)

        Behavior on bodyWidth {
            NumberAnimation {
                duration: Theme.revealMs
                easing.type: Easing.OutCubic
            }
        }

        x: Math.round((root.width - root.boxWidth) / 2)
        width: Math.round(box.bodyWidth)
        // Whatever is left between the two edges. Zero while closed, the full
        // body while open, and on the way through either animation a band that
        // Rectangle draws as a thinning bar — it caps its radius at half the
        // shorter side rather than keeping corners too big for the shape.
        height: box.bottomEdge - box.topEdge
        // The query line and the rows keep their own size through all of that
        // and get cut off by the box's edges, so the list is wiped in from the
        // middle rather than squashed into the gap.
        clip: true
        // Same fill as a bar pill, and for the same reason: the 0.5 alpha is
        // what keeps the compositor blurring behind it.
        color: Theme.popupBg
        radius: Theme.popupRadius

        // Its edge, above everything drawn inside it so that no row's fill
        // can paint over it.
        Rim {
            anchors.fill: parent
            radius: box.radius
            z: 10
        }

        // Deliberately no fade over any of this: the 0.5 alpha above is only
        // just over the 0.3 the compositor's blur rule ignores, so anything
        // that takes the box's opacity down drops the blur out from behind it
        // partway through, which is a far louder event than the fade it was
        // meant to soften.

        // The box is not "off the launcher": clicking its padding should do
        // nothing, not dismiss. Only the screen around it closes.
        MouseArea {
            anchors.fill: parent
        }

        // Placed rather than anchored, because the box's two motions want two
        // different things of it.
        //
        // Through the reveal it has to sit centred, or the box would peel open
        // from a top edge the contents were nailed to and the wipe would come
        // from the top rather than the middle. Once open it has to sit at
        // boxPad and stay there, or the drawer animation below would drag the
        // query line down with the bottom edge — the one thing being looked at
        // while typing would be the one thing that will not hold still.
        //
        // This is both: the term is the centring offset written against the
        // height the box is heading for rather than the one it is drawn at, so
        // it vanishes the moment `reveal` reaches 1 and the list can then grow
        // underneath a query line that does not move. The width still comes
        // from the box, so the rows below can go on sizing off `parent.width`.
        Column {
            id: content

            x: root.boxPad
            y: root.boxPad - box.topEdge
            // The list's width rather than the box's, which are no longer the
            // same thing: what the box grew for the panel is not the list's
            // to lay out in.
            width: root.boxWidth - root.boxPad * 2
            spacing: root.contentGap

            TextInput {
                id: input

                width: parent.width
                height: root.inputHeight
                color: Theme.fg
                selectionColor: Theme.selection
                selectedTextColor: Theme.fg
                font.family: Theme.bodyFont
                font.pixelSize: Theme.queryTextSize
                font.weight: Theme.bodyWeight
                verticalAlignment: TextInput.AlignVCenter
                clip: true

                // What the six first characters do, inside the field and
                // against its right edge, in the quietest step of the label
                // scale. It used to be a line of its own under the query, which
                // made an empty launcher a two-row box with nothing in the top
                // row; it was the field's placeholder before that, which was
                // gone by the time it was any use. Here it stays while the mode
                // it describes does (see Launcher.hint), in the room the query
                // is not using, and gives way as the query reaches it — it is a
                // reference, and never the thing being read.
                Text {
                    id: hint

                    readonly property int clearance: 24
                    readonly property real room: input.width - input.contentWidth - hint.clearance

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(hint.implicitWidth, hint.room)
                    // Gone rather than squeezed to a few letters and an
                    // ellipsis: past a certain point a hint is only noise.
                    visible: Launcher.hint !== "" && hint.room >= Math.min(hint.implicitWidth, 120)
                    text: Launcher.hint
                    color: Theme.label3
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.popupTextSize
                    elide: Text.ElideRight
                }

                focus: true

                // Every way the query arrives from outside the field: the box
                // being built, a reopen inside the fold-away reusing it (the
                // root's onShownChanged), and a mode switched on a box that is
                // already open.
                function adopt(text) {
                    input.text = text;
                    input.cursorPosition = input.text.length;
                    input.forceActiveFocus();
                }

                // Adopts whatever mode the box was opened in. Normally that is
                // nothing at all; Launcher.openWith puts a prefix there before
                // the window exists, and this is what makes the field show it
                // rather than looking empty while the list underneath is
                // already in that mode.
                Component.onCompleted: input.adopt(Launcher.query)

                // Switching modes on a box that is already open — the bar's
                // popups do this, and so does the second of the two keybinds
                // while the first one's box is up.
                Connections {
                    target: Launcher

                    function onQueryReplaced(text) {
                        input.adopt(text);
                    }
                }

                onTextChanged: Launcher.query = input.text

                // Keys handlers run before TextInput's own, so the navigation
                // keys are ours and everything else still types.
                Keys.onPressed: function (event) {
                    const ctrl = event.modifiers & Qt.ControlModifier;

                    switch (event.key) {
                    case Qt.Key_Escape:
                        Launcher.hide();
                        break;
                    // Tab opens and shuts the tree in music mode and moves the
                    // selection everywhere else. Nothing is lost to the swap:
                    // Down, Up and both Ctrl pairs still move the selection.
                    case Qt.Key_Tab:
                        if (Launcher.musicMode) {
                            root.foldTree();
                            break;
                        }
                        if (root.scroll(1))
                            break;
                        Launcher.move(1);
                        break;
                    case Qt.Key_Backtab:
                        if (Launcher.musicMode) {
                            root.foldTree();
                            break;
                        }
                        if (root.scroll(-1))
                            break;
                        Launcher.move(-1);
                        break;
                    case Qt.Key_Down:
                        if (root.scroll(1))
                            break;
                        Launcher.move(1);
                        break;
                    case Qt.Key_Up:
                        if (root.scroll(-1))
                            break;
                        Launcher.move(-1);
                        break;
                    // A page of whichever of the two long things is on
                    // screen: the file under the / list, or an answer too
                    // tall for the box. Never both at once, so they are
                    // simply asked in turn.
                    case Qt.Key_PageDown:
                        if (Launcher.musicMode) {
                            Launcher.skip(1);
                            break;
                        }
                        root.scroll(1) || (preview.item && preview.item.scroll(1));
                        break;
                    case Qt.Key_PageUp:
                        if (Launcher.musicMode) {
                            Launcher.skip(-1);
                            break;
                        }
                        root.scroll(-1) || (preview.item && preview.item.scroll(-1));
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        // Only the music rows read the modifier; see
                        // Launcher.hint for what each one means.
                        Launcher.activate(Launcher.index, ctrl ? "play" : (event.modifiers & Qt.AltModifier) ? "next" : "queue");
                        break;
                    // Drop the row rather than act on it. Only the clipboard
                    // has anything to drop; elsewhere this does nothing, and
                    // plain Delete still edits the query.
                    case Qt.Key_Delete:
                        if (!ctrl)
                            return;
                        Launcher.forget(Launcher.index);
                        break;
                    // Readline's pair and vim's, since both are muscle memory
                    // somewhere on this machine.
                    case Qt.Key_N:
                    case Qt.Key_J:
                        if (!ctrl)
                            return;
                        Launcher.move(1);
                        break;
                    case Qt.Key_P:
                    case Qt.Key_K:
                        if (!ctrl)
                            return;
                        Launcher.move(-1);
                        break;
                    default:
                        // Let the TextInput have it.
                        return;
                    }
                    event.accepted = true;
                }
            }

            // The rule under the query, and only while there is a list under
            // it to rule off. An empty box — nothing typed yet, or a query
            // nothing matched — would otherwise end in a line drawn across
            // nothing. A Column gives an invisible child neither height nor
            // spacing, so this takes the gap it was sitting in with it.
            Rectangle {
                // Out past the padding to both edges of the box: a rule is a
                // line drawn across something, and one that stops short of the
                // sides reads as another item in the column rather than as the
                // division between the query and the answers. A Column sets
                // its children's y and leaves their x alone, which is what
                // makes this possible from inside one.
                x: -root.boxPad
                width: parent.width + root.boxPad * 2
                height: Theme.pillBorder
                visible: list.count > 0
                color: Theme.stroke
            }

            ListView {
                id: list

                // Out to both edges of the box, less the hairline of border
                // on the right. The white rule down the selected row is the
                // row's own left edge and sits on the box's; the far end has
                // nothing to say and simply runs to the outline — up to it,
                // not over it, or the selected row would be the one row with
                // no right-hand edge to it. The rows put the padding back for
                // their own contents.
                x: -root.boxPad
                width: parent.width + root.boxPad * 2 - Theme.pillBorder
                // Short lists draw short, rather than leaving the box padded
                // out with empty rows the way a fixed height would.
                height: Math.min(count, root.visibleRows) * root.rowHeight
                clip: true
                model: Launcher.results

                // Where the pointer was when it last actually moved, in scene
                // coordinates, and whether it has moved at all since the box
                // opened. Both belong to the list rather than to a row: rows
                // are delegates and the one holding this would be recycled.
                property point pointer: Qt.point(-1, -1)
                property bool pointerLive: false

                // The selection lives on the service, so the keyboard and the
                // pointer are both moving the same thing.
                //
                // Told rather than only bound. The model is a plain array and
                // is replaced wholesale on every keystroke, and a ListView
                // resets its own currentIndex when that happens — which goes
                // unseen almost always, because the keystroke that rebuilt the
                // list also moved the selection and the binding put it
                // straight back. There is one case where the list changes and
                // the selection does not: opening the rest of an artist's
                // records. There the grey fill was left on the artist while
                // the selected row, its colour and the sleeve panel had all
                // moved five rows down to the first record revealed.
                //
                // So both events re-tell it, and neither a selection that
                // moves nor a list that changes under a still one can leave
                // the view and the service disagreeing.
                currentIndex: Launcher.index

                Connections {
                    target: Launcher

                    function onIndexChanged() {
                        list.currentIndex = Launcher.index;
                        root.reveal();
                    }
                }

                onCountChanged: list.currentIndex = Launcher.index
                // The selection belongs to the view, not to the row. A row
                // can only be selected or not, so a fill drawn by the delegate
                // can only appear and disappear — while one the view owns is a
                // single object that moves from row to row. Same two marks
                // rofi used, a grey fill and a white rule down the left edge,
                // now sliding between rows instead of blinking between them.
                //
                // Placed from the service's index rather than followed to the
                // view's own current item. A plain array replaced wholesale
                // puts the highlight back at the top of the content before
                // the selection is restored underneath it, and the way back
                // is animated — so every Tab in music mode had the grey bar
                // set off from the first row of the library and fly down the
                // whole list to the row it had never actually left. contentY
                // is reset by the same rebuild and put back in foldTree();
                // this is the other half of that.
                //
                // Every row is the same height, so there is nothing to size
                // to either — which is just as well, because a resize
                // animation on a list that reflows under every keystroke
                // would be a shape changing for no reason.
                highlightFollowsCurrentItem: false
                // The selected row, as the system draws it: a rounded fill
                // held in from the box's edges rather than running out to
                // them, and nothing else marking it. The rule that used to
                // run down its left edge went with the edge-to-edge fill —
                // once the fill is a shape of its own it no longer needs
                // pointing at.
                highlight: Rectangle {
                    x: Theme.selectionInset
                    width: list.width - Theme.selectionInset * 2
                    height: root.rowHeight
                    y: Launcher.index * root.rowHeight
                    visible: list.count > 0
                    radius: Theme.selectionRadius
                    color: Theme.selection

                    // Duration and no velocity: a velocity would cap it, so a
                    // jump from the first row to the last would take as long
                    // as it took to cross, which is most of a second of
                    // sliding.
                    Behavior on y {
                        NumberAnimation {
                            duration: Theme.selectMs
                            easing.type: Easing.OutCubic
                        }
                    }
                }
                // Nothing here scrolls with momentum; a flick that overshoots
                // the ends just looks like the list came loose.
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row

                    required property var modelData
                    required property int index

                    readonly property bool current: Launcher.index === row.index

                    width: ListView.view.width
                    height: root.rowHeight
                    // The fill and the rule that used to be here are the
                    // view's `highlight` above. All that is left of being the
                    // selected row is the colour of its text.
                    color: "transparent"

                    Text {
                        id: title

                        anchors {
                            left: parent.left
                            // The box's padding and the row's own, because the
                            // row itself no longer has any: a title still
                            // starts where it always did — and then however
                            // deep in the music mode's tree this row sits,
                            // which is nothing at all in every other mode.
                            leftMargin: root.boxPad + Theme.pillPad + (row.modelData.indent ?? 0) * root.indentStep
                            verticalCenter: parent.verticalCenter
                        }
                        // Never more than half the row, so a long name cannot
                        // squeeze the subtitle out entirely — the subtitle is
                        // the only thing separating two files both called
                        // config.json. A row with no subtitle has nothing to
                        // protect and gets the line, which is what a clipboard
                        // entry needs.
                        // Half the row is the right reserve when the subtitle
                        // is a path and both halves are competing for it. A row
                        // whose subtitle is a short, fixed thing — a date, a
                        // word — can say so and take the rest, which is what a
                        // task written as a sentence to yourself needs.
                        width: Math.min(implicitWidth, row.width * (row.modelData.titleShare ?? (row.modelData.subtitle ? 0.55 : 0.88)))
                        // rofi lowercased every row it drew, and an app name is
                        // the launcher's to style. A calculated answer, a
                        // command and a copied line are not — they are text
                        // that came from somewhere else and has to come back
                        // out the way it went in.
                        text: row.modelData.raw ? row.modelData.title : row.modelData.title.toLowerCase()
                        color: row.current ? Theme.menuSelectionText : Theme.menuText
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.labelSize
                        font.weight: Theme.bodyWeight
                        elide: Text.ElideRight

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.fadeMs
                            }
                        }
                    }

                    // Where the row came from, on the same line rather than
                    // under the title: app rows have nothing to put here, and a
                    // second line would make every row taller for the sake of
                    // the two modes that do.
                    //
                    // Elided from the left and pushed right, because the end of
                    // a path is the part that identifies it — ".../hypr/configs"
                    // says more than "/home/kutsui/.config/...".
                    Text {
                        anchors {
                            left: title.right
                            leftMargin: 8
                            right: slot.left
                            rightMargin: 6
                            verticalCenter: parent.verticalCenter
                        }
                        visible: text !== ""
                        text: row.modelData.subtitle ?? ""
                        color: Theme.menuText
                        // Under the title even on the row you are on: it is
                        // context, not the thing you picked. Further under it
                        // on a row the history has never seen — see `dim` in
                        // services/Launcher.qml.
                        opacity: row.modelData.dim ? 0.4 : 0.6
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.textSize
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                    }

                    Item {
                        id: slot

                        anchors {
                            right: parent.right
                            // What the row took off the right, less the
                            // border it stops short of: an icon sits the same
                            // distance from the edge of the box as a title
                            // does from the other one.
                            rightMargin: root.boxPad + Theme.pillPad - Theme.pillBorder
                            verticalCenter: parent.verticalCenter
                        }
                        width: root.slotWidth
                        height: root.slotWidth

                        // Same treatment as a taskbar icon (AppIcon.qml): ask
                        // for the name, and fall back to a glyph if nothing
                        // answers. A .desktop file can name an icon no theme on
                        // the machine carries, and a fallback passed to
                        // iconPath is only another name that can miss in turn —
                        // when it does, the row is left with a hole in it.
                        //
                        // themis answers every name the current menu asks for.
                        // This is the net for the one that eventually does not.
                        IconImage {
                            id: icon

                            anchors.centerIn: parent
                            implicitSize: Theme.iconSize
                            source: row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                            // Only Ready counts: a name that resolves to nothing
                            // leaves the image blank rather than erroring, which
                            // would hide the fallback.
                            // Keyed on having an icon name rather than on the
                            // row's kind, so app rows and path rows both land
                            // here without the slot having to know which.
                            visible: !!row.modelData.icon && status === Image.Ready
                        }

                        // Two jobs, because they draw the same thing. A row
                        // can name a glyph outright — the power commands, a
                        // detected domain, a clipboard entry, none of which
                        // has an icon in any theme — and a row that named an
                        // icon nothing answered to falls back to one.
                        Glyph {
                            anchors.centerIn: parent
                            visible: !!row.modelData.glyph || (!!row.modelData.icon && !icon.visible)
                            text: row.modelData.glyph ?? Theme.glyph.window
                            fontSize: Theme.iconSize
                            implicitHeight: Theme.iconSize
                        }

                        // Engine rows have no icon; the key you would be using
                        // goes here instead, so a quote then "y" shows you
                        // landing on YouTube as you type it.
                        Text {
                            anchors.centerIn: parent
                            visible: !!row.modelData.badge
                            text: row.modelData.badge ?? ""
                            color: Theme.fg
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.textSize
                            font.weight: Font.Bold
                        }
                    }

                    // rofi's hover-select: the pointer moves the selection
                    // rather than acting on its own. Emphatically only when it
                    // moves.
                    //
                    // positionChanged also fires when the list moves under a
                    // pointer that is sitting still — a different delegate
                    // arrives beneath the cursor and Qt hands it a move event.
                    // The keyboard then loses every reorder to wherever the
                    // mouse happens to be parked: typing ".au" reset the
                    // selection to 0 and this put it straight back on row 5,
                    // so Enter opened ChatGPT instead of the AUR. The box
                    // opening under the pointer did the same thing.
                    //
                    // So: compare against the last position the pointer was
                    // really at. Scene coordinates, not the row's own, because
                    // the row is the thing that moved. And nothing counts
                    // until the pointer has moved once since the box opened,
                    // or opening under a stationary cursor would still steal
                    // row 0.
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true

                        onPositionChanged: function (mouse) {
                            const p = mapToItem(null, mouse.x, mouse.y);
                            if (!list.pointerLive) {
                                list.pointer = p;
                                list.pointerLive = true;
                                return;
                            }
                            if (Math.abs(p.x - list.pointer.x) < 1 && Math.abs(p.y - list.pointer.y) < 1)
                                return;
                            list.pointer = p;
                            Launcher.selectAt(row.index);
                        }

                        onClicked: Launcher.activate(row.index)
                    }
                }
            }

            // What the model said, under the row that asked it. Three
            // sentences do not go on a 28px line, so this is the one answer in
            // the box that is not a row — it is a paragraph the box grows to
            // fit, and stops growing at the height the list stops at.
            //
            // Past that it scrolls, on the same keys that would have been
            // moving a selection: there is only ever one row in this mode, so
            // Up and Down have nothing else to do. See the Keys handler above.
            Flickable {
                id: answer

                width: parent.width
                height: Math.min(contentHeight, root.visibleRows * root.rowHeight)
                visible: body.text !== ""
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Text {
                    id: body

                    width: answer.width
                    text: Launcher.answerShown
                    color: Theme.menuText
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.labelSize
                    font.weight: Theme.bodyWeight
                    wrapMode: Text.WordWrap
                    // The paragraph is set in from the left the same distance
                    // a row's title is, so the answer starts on the line the
                    // question started on.
                    leftPadding: Theme.pillPad
                    rightPadding: Theme.pillPad
                }
            }
        }

        // The panel, out in the width the box grew for it. Built only in /
        // mode, and kept past it for as long as the box is still wider than
        // the list: it is left where it is and the box's own clip takes it
        // away, so leaving / mode closes over the panel at the speed the box
        // closes rather than blinking it out first.
        //
        // Its y is the Column's, so the reveal wipes the two in together.
        Loader {
            id: preview

            x: root.boxWidth - root.boxPad + root.panelGap
            y: content.y
            width: root.panelWidth
            height: Math.round(box.bodyHeight) - root.boxPad * 2
            active: Launcher.pathMode || (!Launcher.musicMode && box.bodyWidth > root.boxWidth)

            sourceComponent: FilePreview {
                // Files only. A directory has no picture in it, and its row is
                // a place to go rather than a thing to look at.
                path: Launcher.pathMode && Launcher.selected && Launcher.selected.kind === "path" && !Launcher.selected.dir ? Launcher.selected.path : ""
            }
        }

        // The other panel, in the same slot: the two modes that grow one never
        // do it at the same time. Its own component rather than a mode inside
        // FilePreview, which shells out to a thumbnailer because a path can be
        // any kind of file at all — where this is always a picture already
        // sitting in the folder with the music.
        //
        // Built only in # mode. It has always blinked out on leaving it rather
        // than being clipped away, so there is no fold-away to keep it for.
        Loader {
            x: root.boxWidth - root.boxPad + root.panelGap
            y: content.y
            width: root.panelWidth
            height: Math.round(box.bodyHeight) - root.boxPad * 2
            active: Launcher.musicMode

            sourceComponent: CoverArt {
                dir: Launcher.coverDir
                // The row's own two lines, which the panel has the width to
                // wrap and the row does not.
                title: Launcher.selected ? Launcher.selected.title : ""
                subtitle: Launcher.selected ? (Launcher.selected.subtitle ?? "") : ""
                glyph: Launcher.selected ? (Launcher.selected.glyph ?? "") : ""
            }
        }
    }
}

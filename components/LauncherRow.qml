import QtQuick
import Quickshell
import Quickshell.Widgets
import qs
import qs.services

// Draw one launcher result, keeping row rendering apart from list navigation.
Rectangle {
    required property var menu

    id: row

    required property var modelData
    required property int index

    readonly property bool current: Launcher.index === row.index
    readonly property real enterProgress: Theme.reduceMotion ? 1 : Math.max(0, Math.min(1, (row.menu.rowsReveal * row.menu.rowRevealMs - Math.min(row.index, row.menu.visibleRows - 1) * row.menu.rowStaggerMs) / 100))

    width: ListView.view.width
    height: row.menu.rowHeight
    // The fill is the view's `highlight` above; all that marks
    // the selected row here is the colour of its text.
    color: "transparent"
    opacity: row.enterProgress * (row.modelData.crossed ? 0.45 : 1)
    transform: Translate { y: 6 * (1 - row.enterProgress) }

    Text {
        id: title

        anchors {
            left: parent.left
            // The box's padding and the row's own, because the
            // row itself no longer has any: a title still
            // starts where it always did — and then however
            // deep in the music mode's tree this row sits,
            // which is nothing at all in every other mode.
            leftMargin: row.menu.boxPad + Theme.popupInset + (row.modelData.indent ?? 0) * row.menu.indentStep
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
        // An app name is the launcher's to style, so it is
        // lowercased. A calculated answer, a
        // command and a copied line are not — they are text
        // that came from somewhere else and has to come back
        // out the way it went in.
        // A timer's title counts down, so it is read live
        // here rather than carried in the row: a row that
        // changed every second would rebuild the list every
        // second. See Launcher.timerResults.
        text: {
            const d = row.modelData;
            const t = d.kind === "timer" ? Timers.describe(d.entry) : d.title;
            return d.raw ? t : t.toLowerCase();
        }
        color: row.current ? Theme.menuSelectionText : Theme.menuText
        font.family: Theme.bodyFont
        font.pixelSize: Theme.labelSize
        font.weight: Theme.bodyWeight
        font.strikeout: !!row.modelData.crossed
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
        // An armed power row's question is the one subtitle meant
        // to be read before Enter, so it is the warning colour at
        // full strength.
        color: row.modelData.armed ? Theme.warn : Theme.menuText
        // Under the title even on the row you are on: it is
        // context, not the thing you picked. Further under it
        // on a row the history has never seen — see `dim` in
        // services/Launcher.qml.
        opacity: row.modelData.armed ? 1 : row.modelData.dim ? 0.4 : 0.6
        font.family: Theme.bodyFont
        font.pixelSize: Theme.captionSize
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
    }

    Item {
        id: slot

        anchors {
            right: parent.right
            // Match the title's inset on the opposite edge.
            rightMargin: row.menu.boxPad + Theme.popupInset
            verticalCenter: parent.verticalCenter
        }
        width: row.menu.slotWidth
        height: row.menu.slotWidth
        // Let the queue control take its click before the result row.
        z: 1

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
            color: row.modelData.armed ? Theme.warn : Theme.fg
            fontSize: Theme.iconSize
            implicitHeight: Theme.iconSize
        }

        // Engine rows have no icon; the key you would be using
        // goes here instead, so "." then "y" shows you
        // landing on YouTube as you type it.
        Text {
            anchors.centerIn: parent
            visible: !!row.modelData.badge
            text: row.modelData.badge ?? ""
            color: Theme.fg
            font.family: Theme.bodyFont
            font.pixelSize: Theme.captionSize
            font.weight: Font.Bold
        }

        ClickArea {
            id: queueControl
            anchors.fill: parent
            visible: row.modelData.kind === "music-queue" && !!row.modelData.glyph
            enabled: Mpd.connected
            cursorShape: Qt.PointingHandCursor
            name: (row.modelData.glyph === Theme.glyph.paused ? "Pause " : "Play ") + row.modelData.title
            actions: ({ [Qt.LeftButton]: () => Launcher.activate(row.index) })
        }
    }

    // Hover selects: the pointer moves the selection
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
        Accessible.role: Accessible.Button
        Accessible.name: row.modelData.title || row.modelData.subtitle || "Launcher result"
        Accessible.ignored: row.modelData.kind === "note"
        Accessible.onPressAction: if (enabled && visible)
            Launcher.activate(row.index)

        onPositionChanged: function (mouse) {
            const p = mapToItem(null, mouse.x, mouse.y);
            if (!row.ListView.view.pointerLive) {
                row.ListView.view.pointer = p;
                row.ListView.view.pointerLive = true;
                return;
            }
            if (Math.abs(p.x - row.ListView.view.pointer.x) < 1 && Math.abs(p.y - row.ListView.view.pointer.y) < 1)
                return;
            row.ListView.view.pointer = p;
            Launcher.selectAt(row.index);
        }

        onClicked: Launcher.activate(row.index)

        onWheel: function (wheel) {
            if (wheel.angleDelta.y < 0 || wheel.pixelDelta.y < 0)
                row.menu.loadUnreadMore(Math.ceil((row.ListView.view.contentY + row.ListView.view.height) / row.menu.rowHeight));
            wheel.accepted = false;
        }
    }
}

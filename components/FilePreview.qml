import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.components

// What the file the / list is sitting on actually looks like.
//
// Every other mode answers in text, because what it is ranking is text. A
// path list is not: two directories of photographs read identically written
// down, and the only thing that tells them apart is the picture. So this
// panel, and only in / mode — LauncherMenu.qml is where the box widens to
// make room for it.
//
// ~/_scripts/thumb.sh does the rendering and the keeping; everything here is
// about not asking it too often. Holding Down through forty files must not
// leave forty ffmpegs behind it, so the ask is debounced and queued exactly
// the way the launcher's other shelling-out modes are — see Launcher.pump,
// which this is a second copy of because the panel is a component and the
// service's copy belongs to the service.
Item {
    id: root

    // The file to draw, or "" for everything with no picture in it: a
    // directory, an empty list, a mode that is not /.
    property string path: ""

    readonly property string script: Quickshell.env("HOME") + "/_scripts/thumb.sh"

    // What the script said for a path: { kind, payload }. Kept for the life
    // of the window rather than forever — the script has a real cache on
    // disk, and this is only here so that arrowing back up a list does not
    // shell out a second time.
    //
    // Written to in place, so nothing may bind to it. `kind` and `payload`
    // below are the properties that move.
    property var known: ({})

    // The answer for the file on screen: "image" and something to draw, or
    // "text" and the head of a file to set, or neither. Set rather than
    // bound, because it arrives from a process.
    property string kind: ""
    property string payload: ""

    // file:// and a path that can contain anything. encodeURI leaves the
    // slashes where they are and takes the spaces; # and ? it leaves behind,
    // and a URL would read them as a fragment and a query.
    function fileUrl(p) {
        return "file://" + encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F");
    }

    onPathChanged: {
        const hit = root.known[root.path];
        if (hit !== undefined) {
            // Already asked. An empty kind is an answer too — the file has
            // nothing to show — so this is a check against undefined rather
            // than against "".
            root.kind = hit.kind;
            root.payload = hit.payload;
            thumb.want = "";
            debounce.stop();
            return;
        }
        root.kind = "";
        root.payload = "";
        // Back to the top: the last file's scroll position means nothing in
        // this one.
        bodyView.contentY = 0;
        thumb.want = root.path;
        if (thumb.want)
            debounce.restart();
        else
            debounce.stop();
    }

    // A page of the text, up or down, for a file longer than the panel.
    // Returns whether there was anywhere to go: the box asks this and the
    // answer block in turn, and whichever has something to scroll takes the
    // key. See LauncherMenu.qml.
    function scroll(dir): bool {
        if (!bodyView.visible || bodyView.contentHeight <= bodyView.height)
            return false;
        // A page less two lines, so the lines being read carry over the jump
        // rather than the page turning out from under them.
        const step = Math.max(bodyView.height - body.font.pixelSize * 2, body.font.pixelSize);
        bodyView.contentY = Math.max(0, Math.min(bodyView.contentHeight - bodyView.height, bodyView.contentY + dir * step));
        return true;
    }

    function pump(): void {
        if (thumb.running || thumb.want === thumb.arg)
            return;
        thumb.arg = thumb.want;
        if (thumb.arg)
            thumb.running = true;
    }

    Process {
        id: thumb

        property string want: ""
        property string arg: ""

        command: [root.script, thumb.arg]

        // A run that finishes to find the selection has moved on restarts the
        // clock rather than starting the next one itself, or the debounce
        // would hold back the first ask and none of the ones after it.
        onExited: if (thumb.want !== thumb.arg)
            debounce.restart()

        stdout: StdioCollector {
            onStreamFinished: {
                // First line is what kind of answer this is, the rest is the
                // answer. A path has the newline the script printed after it
                // and nothing else worth keeping; a file's contents keep
                // every newline they came with.
                const cut = text.indexOf("\n");
                const kind = cut < 0 ? "" : text.slice(0, cut);
                const answer = ({
                        kind: kind,
                        payload: kind === "image" ? text.slice(cut + 1).trim() : (kind === "text" ? text.slice(cut + 1) : "")
                    });
                root.known[thumb.arg] = answer;
                // Only if it is still the file being looked at: a soffice
                // render can land a second after the row it belongs to has
                // gone by.
                if (thumb.arg === root.path) {
                    root.kind = answer.kind;
                    root.payload = answer.payload;
                }
            }
        }
    }

    Timer {
        id: debounce

        // Long enough to sit out a held arrow key, which repeats at about
        // 30ms once it gets going, and short enough that landing on a row and
        // stopping feels like the picture was already there.
        interval: 160
        onTriggered: root.pump()
    }

    Image {
        id: shot

        anchors.fill: parent
        source: root.kind === "image" ? root.fileUrl(root.payload) : ""
        fillMode: Image.PreserveAspectFit
        // The panel is small and the file may not be: decoded to twice the
        // box it is drawn in, which is sharp on a scaled screen and still a
        // fraction of what a full-size photograph would cost.
        sourceSize.width: Math.round(root.width * 2)
        sourceSize.height: Math.round(root.height * 2)
        // Loaded off the render thread, so a slow decode cannot stall the
        // list the arrow keys are moving.
        asynchronous: true
        smooth: true
        visible: opacity > 0
        // Ready and nothing else: a file that fails to decode leaves the
        // glyph up rather than a hole where a picture was meant to be.
        opacity: shot.status === Image.Ready ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.fadeMs
                easing.type: Easing.OutCubic
            }
        }
    }

    // A text file is read rather than looked at, so it is set as text: the
    // head of it in the mono font, at the size that fits the most of it while
    // still being a size. Not wrapped — code is written in lines, and a line
    // that runs off the edge says more about the file than the same line
    // folded into three.
    //
    // In something that scrolls, because a panel holds twenty-odd lines and
    // the script sends eighty. Vertically only: contentWidth is the panel's,
    // so a long line stays cut off at the edge rather than letting the whole
    // page drift sideways.
    Flickable {
        id: bodyView

        anchors.fill: parent
        contentHeight: body.implicitHeight
        contentWidth: width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: opacity > 0
        opacity: root.kind === "text" ? 0.75 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.fadeMs
                easing.type: Easing.OutCubic
            }
        }

        Text {
            id: body

            width: bodyView.width
            text: root.payload
            // Plain, always: this is someone else's file, and a markdown
            // heading in it is a line starting with a hash, not a heading.
            textFormat: Text.PlainText
            color: Theme.menuText
            font.family: Theme.monoFont
            font.pixelSize: 9
            wrapMode: Text.NoWrap
        }
    }

    // What is there the rest of the time: while the render runs, for a
    // directory, and for the files that have nothing to show either way.
    // Deliberately the same weight as the rest of the box rather than a
    // spinner — the panel filling in is already the only thing moving on that
    // side.
    Glyph {
        anchors.centerIn: parent
        text: root.path === "" ? Theme.glyph.folder : Theme.glyph.file
        color: Theme.menuText
        opacity: shot.opacity > 0 || bodyView.opacity > 0 ? 0 : 0.25
        fontSize: Math.round(Math.min(parent.width, parent.height) * 0.4)
        implicitHeight: fontSize

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.fadeMs
                easing.type: Easing.OutCubic
            }
        }
    }
}

import QtQuick
import Quickshell
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
// the way the launcher's other shelling-out modes are — see QueuedProcess.
Item {
    id: root

    // The file to draw, or "" for everything with no picture in it: a
    // directory, an empty list, a mode that is not /.
    property string path: ""

    readonly property string script: Paths.script("thumb.sh")

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
        // Back to the top before anything else: the last file's scroll
        // position means nothing in this one, cached or not.
        bodyView.contentY = 0;
        const hit = root.known[root.path];
        if (hit !== undefined) {
            // Already asked. An empty kind is an answer too — the file has
            // nothing to show — so this is a check against undefined rather
            // than against "".
            root.kind = hit.kind;
            root.payload = hit.payload;
            thumb.want = "";
            return;
        }
        root.kind = "";
        root.payload = "";
        thumb.want = root.path;
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

    QueuedProcess {
        id: thumb

        // Long enough to sit out a held arrow key, which repeats at about
        // 30ms once it gets going, and short enough that landing on a row and
        // stopping feels like the picture was already there.
        interval: 160
        command: [root.script, thumb.arg]

        onResult: function (arg, text) {
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
            root.known[arg] = answer;
            // Only if it is still the file being looked at: a soffice
            // render can land a second after the row it belongs to has
            // gone by.
            if (arg === root.path) {
                root.kind = answer.kind;
                root.payload = answer.payload;
            }
        }
    }

    // --- the picture ---------------------------------------------------------

    // Two Images taking turns rather than one changing source. An Image drops
    // to Loading the moment its source moves, even to a file it decoded a
    // second ago, so one Image meant the glyph flashing up between two
    // pictures that were both already cached. Here the one on screen holds
    // its frame until the other has the next file Ready, and only then do
    // they swap.
    property Image front: null
    property Image next: null

    readonly property string imageUrl: root.kind === "image" ? root.fileUrl(root.payload) : ""

    onImageUrlChanged: {
        root.next = null;
        if (!root.imageUrl) {
            root.front = null;
            return;
        }
        if (root.front && String(root.front.source) === root.imageUrl)
            return;
        const img = root.front === shotA ? shotB : shotA;
        img.source = root.imageUrl;
        // A source it already held decodes nothing and changes no status, so
        // the swap has to be made here rather than waited for.
        if (img.status === Image.Ready)
            root.front = img;
        else
            root.next = img;
    }

    function landed(img): void {
        if (root.next === img && img.status === Image.Ready) {
            root.front = img;
            root.next = null;
        }
    }

    // Nothing in here reaches for `root`: an inline component is its own
    // scope, so what differs between the two is set where they are made.
    component Shot: Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        // The panel is small and the file may not be: decoded to twice the
        // box it is drawn in, which is sharp on a scaled screen and still a
        // fraction of what a full-size photograph would cost. Square on the
        // width alone: the height animates with the list, and a decode size
        // bound to it would re-decode the file on every frame of that.
        sourceSize.width: Math.round(width * 2)
        sourceSize.height: Math.round(width * 2)
        // Loaded off the render thread, so a slow decode cannot stall the
        // list the arrow keys are moving.
        asynchronous: true
        smooth: true
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.fadeMs
                easing.type: Easing.OutCubic
            }
        }
    }

    // Only a Ready image is ever made `front`, so a file that fails to decode
    // leaves the glyph up rather than a hole where a picture was meant to be.
    Shot {
        id: shotA

        opacity: root.front === shotA ? 1 : 0
        onStatusChanged: root.landed(shotA)
    }

    Shot {
        id: shotB

        opacity: root.front === shotB ? 1 : 0
        onStatusChanged: root.landed(shotB)
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
            font.pixelSize: Theme.previewTextSize
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
        opacity: root.front !== null || bodyView.opacity > 0 ? 0 : 0.25
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

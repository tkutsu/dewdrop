import QtQuick
import Quickshell
import qs
import qs.components

// A preview of the file the / list is on; only / mode shows it
// (LauncherMenu.qml widens the box). ~/_scripts/thumb.sh renders and caches;
// the ask is debounced through QueuedProcess so holding Down through forty
// files does not leave forty ffmpegs behind.
Item {
    id: root

    // The file to draw, or "" for everything with no picture in it: a
    // directory, an empty list, a mode that is not /.
    property string path: ""

    readonly property string script: Paths.script("thumb.sh")

    // Path → { kind, payload } for the life of the window, so arrowing back
    // up does not shell out again (the script keeps the real cache). Written
    // in place, so nothing may bind to it; bind to `kind` and `payload`.
    property var known: ({})

    // The file on screen: "image" and a path, "text" and its head, or "".
    property string kind: ""
    property string payload: ""

    // encodeURI leaves # and ?, which a URL would read as fragment and query.
    function fileUrl(p) {
        return "file://" + encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F");
    }

    onPathChanged: {
        bodyView.contentY = 0;
        const hit = root.known[root.path];
        if (hit !== undefined) {
            // An empty kind is an answer too: nothing to show.
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
    function scroll(dir): void {
        if (!bodyView.visible || bodyView.contentHeight <= bodyView.height)
            return;
        // A page less two lines, so the lines being read carry over.
        const step = Math.max(bodyView.height - body.font.pixelSize * 2, body.font.pixelSize);
        bodyView.contentY = Math.max(0, Math.min(bodyView.contentHeight - bodyView.height, bodyView.contentY + dir * step));
    }

    QueuedProcess {
        id: thumb

        // Sits out a held arrow key (~30ms repeat) without feeling late.
        interval: 160
        command: [root.script, thumb.arg]

        onResult: function (arg, text) {
            // First line is the kind, the rest the answer: an image path
            // trimmed, a text head kept with its newlines.
            const cut = text.indexOf("\n");
            const kind = cut < 0 ? "" : text.slice(0, cut);
            const answer = ({
                    kind: kind,
                    payload: kind === "image" ? text.slice(cut + 1).trim() : (kind === "text" ? text.slice(cut + 1) : "")
                });
            root.known[arg] = answer;
            // A slow render (soffice) can land after its row has gone by.
            if (arg === root.path) {
                root.kind = answer.kind;
                root.payload = answer.payload;
            }
        }
    }

    // --- the picture ---------------------------------------------------------

    // Two Images taking turns: an Image drops to Loading as soon as its
    // source moves, so the one on screen holds its frame until the other is
    // Ready with the next file, and only then do they swap.
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
        // A source it already held changes no status, so swap here.
        if (img.status === Image.Ready)
            root.front = img;
        else if (img.status === Image.Error)
            root.front = null;
        else
            root.next = img;
    }

    function landed(img): void {
        if (root.next === img && img.status === Image.Ready) {
            root.front = img;
            root.next = null;
        } else if (root.next === img && img.status === Image.Error) {
            root.front = null;
            root.next = null;
        }
    }

    // An inline component is its own scope: no `root` in here.
    component Shot: Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        readonly property real dpr: QsWindow.window?.devicePixelRatio ?? 1
        // Decoded at the box's size in screen pixels, from the width alone:
        // the height animates with the list and would re-decode the file
        // every frame.
        sourceSize.width: Math.ceil(width * dpr)
        sourceSize.height: Math.ceil(width * dpr)
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

    // Only a Ready image becomes `front`, so a failed decode leaves the glyph.
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

    // A text file's head in the mono font, unwrapped: code is written in
    // lines. Scrolls vertically only (the script sends eighty lines), so a
    // long line is cut at the edge rather than the page drifting sideways.
    Flickable {
        id: bodyView
        // In the accessibility tree as a list to scroll, half a view a step.
        Accessible.role: Accessible.List
        Accessible.name: "Preview"
        Accessible.onScrollUpAction: contentY = Math.max(originY, contentY - height / 2)
        Accessible.onScrollDownAction: contentY = Math.min(originY + Math.max(0, contentHeight - height), contentY + height / 2)

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
            // Someone else's file: a markdown heading is just a line here.
            textFormat: Text.PlainText
            color: Theme.menuText
            font.family: Theme.monoFont
            font.pixelSize: Theme.previewTextSize
            wrapMode: Text.NoWrap
        }
    }

    // Shown while rendering, for a directory, and for files with nothing to
    // show. Not a spinner: the panel filling in is motion enough.
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

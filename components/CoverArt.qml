import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import qs
import qs.components

// The artwork for whatever row the launcher's # mode is sitting on.
//
// The same errand FilePreview.qml runs for / mode, and the same reason for
// running it: a list of records read as text is a list of words, and the thing
// that tells one from another is the sleeve. Nothing like the same machinery,
// though — that panel shells out to a thumbnailer because a path can be any
// kind of file at all, where this is always a picture already sitting in the
// folder with the music.
//
// Found by listing the directory rather than by trying each candidate name as
// an image source: a miss there is a failed file open per name, logged. Which
// is how services/Mpd.qml finds the sleeve for the track that is playing —
// this widens what counts as one, for the reason set out below.
Item {
    id: root

    // Absolute, with its trailing slash — Library.coverDir's shape.
    property string dir: ""
    property string title: ""
    property string subtitle: ""
    // What to draw when the folder has no picture in it, so an artist with no
    // sleeve still gets the mark of what it is rather than an empty panel.
    property string glyph: ""
    readonly property real dpr: QsWindow.window?.devicePixelRatio ?? 1

    // The four names first, and then whatever else is in there. Measured over
    // this library: 274 of the 760 folders holding music name their picture
    // one of the four, another 155 have one under some other name, and 331
    // have no picture at all. Stopping at the four names would leave the panel
    // empty two times in three, which reads as a panel that does not work
    // rather than as a folder with no sleeve in it.
    //
    // Deliberately not pushed back into Mpd.cover, which is the same lookup
    // for the track that is playing: that one has been right about the popup
    // for as long as the popup has existed, and widening what counts as a
    // sleeve is a change to make on purpose rather than in passing.
    readonly property string cover: {
        // First, because a FolderListModel pointed at an empty folder does not
        // empty itself — it keeps whatever it last listed. Without this the
        // panel held the previous row's sleeve up against a playlist's name,
        // which is worse than the blank it is meant to be: it is a picture of
        // the wrong thing, labelled.
        if (!root.dir)
            return "";
        if (named.count > 0)
            return named.get(0, "fileUrl");
        // The eighteen "Cover Back.jpg" in here are the back of the sleeve,
        // which is the track listing. It is the right record and the wrong
        // side of it, so it is what to fall back to last rather than first.
        for (let i = 0; i < loose.count; i++) {
            if (!/back/i.test(String(loose.get(i, "fileName"))))
                return loose.get(i, "fileUrl");
        }
        return loose.count > 0 ? loose.get(0, "fileUrl") : "";
    }

    FolderListModel {
        id: named

        folder: root.dir ? "file://" + root.dir : ""
        showDirs: false
        sortField: FolderListModel.Name
        nameFilters: ["cover.*", "folder.*", "front.*", "album.*"]
        caseSensitive: false
    }

    FolderListModel {
        id: loose

        folder: root.dir ? "file://" + root.dir : ""
        showDirs: false
        sortField: FolderListModel.Name
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.bmp"]
        caseSensitive: false
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        // Against the top of the panel rather than centred in it. The panel is
        // as tall as the list beside it and the list changes length under
        // every keystroke; a sleeve that slid up and down the box as rows came
        // and went would be the one thing on screen not holding still.
        anchors.top: parent.top
        spacing: 8

        // Square, because a sleeve is. The frame is drawn whether or not
        // there is anything in it, so the caption underneath sits on the same
        // line for every row rather than climbing when a folder has no
        // picture.
        Rectangle {
            width: parent.width
            height: parent.width
            color: Theme.well
            radius: 3
            clip: true

            Image {
                id: art

                anchors.fill: parent
                source: root.cover
                fillMode: Image.PreserveAspectCrop
                // Decoded at the box's size in screen pixels, a fraction of
                // what the 1400px scans in some of these folders would cost.
                sourceSize.width: Math.ceil(root.width * root.dpr)
                sourceSize.height: Math.ceil(root.width * root.dpr)
                // Off the render thread, so a slow decode cannot stall the
                // list the arrow keys are moving.
                asynchronous: true
                smooth: true
                visible: opacity > 0
                // Ready and nothing else: a file that fails to decode leaves
                // the glyph up rather than a hole where a sleeve should be.
                opacity: art.status === Image.Ready ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.fadeMs
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Glyph {
                anchors.centerIn: parent
                text: root.glyph
                color: Theme.menuText
                opacity: art.opacity > 0 ? 0 : 0.25
                fontSize: Math.round(parent.width * 0.35)
                implicitHeight: fontSize

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.fadeMs
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // The row's own two lines again, wrapped rather than elided. Not a
        // repetition for its own sake: a row is one line and cuts a long
        // album's name off in the middle of it, and the whole reason to look
        // at the panel is to find out which record this actually is.
        Text {
            width: parent.width
            text: root.title
            color: Theme.menuText
            font.family: Theme.bodyFont
            font.pixelSize: Theme.labelSize
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            visible: text !== ""
            text: root.subtitle
            color: Theme.menuText
            opacity: 0.6
            font.family: Theme.bodyFont
            font.pixelSize: Theme.captionSize
            font.weight: Theme.bodyWeight
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }
}

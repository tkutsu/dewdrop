import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs
import qs.components
import qs.services

// The music pill: what is playing, with a hand either side of it. The title is
// the play/pause button, sleeve included — it is the widest thing in the pill
// and the one you are already looking at, so it is also the cheapest to hit.
//
// The three are TapHandlers rather than the BarItem's own click, which stays
// unused here: one module, three targets, and a handler on the item that draws
// each one is what keeps them from having to be told apart by pointer position.
BarItem {
    id: root

    // For the pill around it, which is this module and nothing else and so
    // is drawn into its neighbour with it when there is nothing to play: the
    // bar draws the pill off `reveal` (see Bar.drop), and nothing folds.
    stowed: !Mpd.loaded || !Settings.moduleOn("music")
    folds: false
    // And for the outline it draws: how far through the track we are. Held
    // like the title below, so the line fades with the pill rather than
    // dropping out the moment the queue empties.
    property real progress: 0

    Binding {
        root.progress: Mpd.duration > 0 ? Mpd.elapsed / Mpd.duration : 0
        when: Mpd.loaded
        restoreMode: Binding.RestoreNone
    }

    // The title, kept while the pill goes: the queue is empty before the pill
    // has gone, and the line should not blank on the way. Bound only
    // while there is something to show and left holding the last value after.
    property string shownLabel: ""

    Binding {
        root.shownLabel: Mpd.label
        when: Mpd.loaded
        restoreMode: Binding.RestoreNone
    }

    spacing: Theme.mediaGap
    popup: MusicPopup {}
    // Left is the three targets, so the popup is right.
    popupButton: Qt.RightButton
    // Each target presses in by itself; the pill as a whole does not.
    dips: false

    Glyph {
        Layout.fillHeight: true
        text: Theme.glyph.mediaPrev
        transform: Translate { y: prevTap.pressed ? Theme.pressDip : 0 }

        TapHandler {
            id: prevTap
            onTapped: Mpd.send(["prev"])
        }
    }

    // The play/pause button: the sleeve and the title, and the gap between
    // them, as one target that presses in together.
    RowLayout {
        Layout.fillHeight: true
        spacing: root.spacing
        transform: Translate { y: toggleTap.pressed ? Theme.pressDip : 0 }

        TapHandler {
            id: toggleTap
            onTapped: Mpd.send(["toggle"])
        }

        // The sleeve, as the title's own icon. It is the one spot of colour on
        // a bar that is otherwise white on dark, and it changes with every
        // record — the thing that says which album this is before the title
        // has been read. The popup already had the picture; this is a
        // thumbnail of the same file.
        //
        // Icon-sized and only just rounded, so it reads as part of the row
        // rather than as a second pill inside this one. Only there once the
        // picture is: a folder with no sleeve gives the pill no empty square,
        // just the controls it always had.
        Item {
            readonly property int size: 14
            readonly property int air: (Theme.barHeight - size) / 2

            Layout.fillHeight: true
            implicitWidth: size
            visible: sleeve.status === Image.Ready

            ClippingRectangle {
                y: Theme.pillTop(parent.height) + parent.air
                width: parent.size
                height: parent.size
                radius: 3
                color: "transparent"

                Image {
                    id: sleeve

                    anchors.fill: parent
                    source: Mpd.cover
                    fillMode: Image.PreserveAspectCrop
                    // Decoded at twice the size it is drawn, not at the size of
                    // the scan: some of these are 1400px across.
                    sourceSize.width: parent.width * 2
                    sourceSize.height: parent.height * 2
                    asynchronous: true
                    smooth: true
                    mipmap: true
                }
            }
        }

        BarText {
            Layout.fillHeight: true
            text: root.shownLabel
            maxWidth: Theme.mediaTitleWidth
            // Paused is the title gone quiet rather than a second icon saying
            // so. The pill is two glyphs and a line of text; a third glyph in
            // it would be the one thing there that cannot be pressed.
            opacity: Mpd.state === "play" ? 1 : Theme.dimOpacity

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.fadeMs
                }
            }
        }
    }

    Glyph {
        Layout.fillHeight: true
        text: Theme.glyph.mediaNext
        transform: Translate { y: nextTap.pressed ? Theme.pressDip : 0 }

        TapHandler {
            id: nextTap
            onTapped: Mpd.send(["next"])
        }
    }

    onScrollUp: Mpd.send(["seek", "-10"])
    onScrollDown: Mpd.send(["seek", "+10"])
}

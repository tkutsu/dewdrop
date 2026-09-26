import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services

// The flat-colour wallpaper, drawn here rather than left to hyprpaper.
//
// hyprpaper does fade between wallpapers, but it takes the outgoing one down
// before the incoming one is up: the screen dips about a fifth of the way to
// black on the way past (measured against this build, hyprpaper 0.8.4, 2026-09)
// and on a slider drag that reads as the background flashing. A colour drawn
// here is interpolated straight from the old to the new, with nothing in the
// middle that is neither.
//
// hyprpaper still gets every colour — services/Wallpaper.qml goes on writing
// the one-pixel PNG — because it is what holds the wallpaper while the shell is
// not running, and what shows through the instant this surface is torn down. It
// does its dip underneath an opaque copy of the same colour, where nobody sees
// it.
PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    // Bottom, not Background: hyprpaper's own surface is on Background, and two
    // surfaces on one layer are ordered by who got there first. Bottom is above
    // all of Background and below every window, which is the whole of what a
    // wallpaper has to be.
    WlrLayershell.namespace: "quickshell:backdrop"
    WlrLayershell.layer: WlrLayer.Bottom

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    // A wallpaper reserves nothing and is never clicked. Without the empty mask
    // this would swallow every press that misses a window.
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    color: "transparent"

    // Mapped only while there is a colour to draw or one still fading out.
    // A surface left up under an image wallpaper is two full-screen buffers
    // held for nothing and a transparent blend in every repaint on top of it.
    // Taken off the rectangle's opacity rather than off Wallpaper.color, so
    // the fade to an image finishes before the surface goes.
    visible: shade.opacity > 0

    // The colour to draw, which is not quite the colour that is set: it holds
    // its value through the image that replaces it, so fading out is this
    // colour going transparent rather than a slide through some other one on
    // the way. Fading back in from the same place is what makes returning to a
    // colour look like the image lifting off it.
    property color shown: "transparent"

    // Off `onScreen` rather than `color`: with drift on, the two differ by
    // wherever the time of day has taken the colour (see Wallpaper.drift).
    function adopt() {
        if (Wallpaper.onScreen)
            root.shown = Wallpaper.onScreen;
    }

    Component.onCompleted: root.adopt()

    Connections {
        target: Wallpaper

        function onOnScreenChanged() {
            root.adopt();
        }
    }

    Rectangle {
        id: shade

        anchors.fill: parent
        color: root.shown
        // Down to nothing while an image is up, so hyprpaper's wallpaper is
        // what the screen shows and this is not in the way of it.
        opacity: Wallpaper.color ? 1 : 0

        // The fade the whole file is for. Same pace as everything else on the
        // bar; a drag lands a new colour every 60ms and this trails it.
        Behavior on color {
            ColorAnimation {
                duration: Theme.fadeMs
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.fadeMs
            }
        }
    }
}

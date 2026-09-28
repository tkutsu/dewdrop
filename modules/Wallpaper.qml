import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// custom/wallpaper. Stage 4 turns the "12/47" tooltip into a thumbnail grid.
BarItem {
    popup: WallpaperPopup {}
    // A tool, like the screenshot button: nothing about it is ever news.
    quiet: true

    // Dimmed until the saved wallpaper is back on the screen.
    opacity: Wallpaper.restored ? 1 : Theme.dimOpacity

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.fadeMs
        }
    }

    Glyph {
        Layout.fillHeight: true
        text: Theme.glyph.wallpaper
    }

    // Singletons are built on first use, and the boot-time restore lives in
    // this one's own Component.onCompleted. The call is only the touch that
    // builds it; by the time it runs the singleton's scan is already going and
    // this returns without doing anything. (Backdrop reads Wallpaper.color
    // too, so it is no longer the only touch, but it is the one that says so.)
    Component.onCompleted: Wallpaper.rescan()

    // Left is the popup (BarItem.popupButton); right is the folder.
    actions: ({
            [Qt.RightButton]: () => Wallpaper.openFolder()
        })

    onScrollUp: Wallpaper.prev()
    onScrollDown: Wallpaper.next()
}

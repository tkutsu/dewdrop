import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// Open the wallpaper picker and colour controls.
BarItem {
    tooltip: "Wallpaper"
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
        fontSize: Theme.glyphSize - 2
    }

    // Singletons are built on first use, and the boot-time restore lives in
    // this one's own Component.onCompleted. The call is only the touch that
    // builds it; by the time it runs the singleton's scan is already going and
    // this returns without doing anything. (Backdrop reads Wallpaper.color
    // too, so it is no longer the only touch, but it is the one that says so.)
    Component.onCompleted: Wallpaper.rescan()

    // Left is the popup (BarItem.popupButton); right is the folder.
    actions: ({
            [Qt.RightButton]: () => {
                OpenPopup.dismiss();
                Wallpaper.openFolder();
            }
        })

    onScrollUp: Wallpaper.next()
    onScrollDown: Wallpaper.prev()
}

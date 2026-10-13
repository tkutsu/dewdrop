import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// Open the wallpaper picker and colour controls.
BarItem {
    name: "Wallpaper"
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

    // Left is the popup (BarItem.popupButton); right is the folder.
    actions: ({
            [Qt.RightButton]: () => {
                OpenPopup.dismiss();
                Wallpaper.openFolder();
            }
        })

    scrolls: true
    Accessible.onScrollUpAction: scrollUp()
    Accessible.onScrollDownAction: scrollDown()
    onScrollUp: Wallpaper.next()
    onScrollDown: Wallpaper.prev()
}

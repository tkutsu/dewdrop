import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// custom/language: left click lists the layouts, right click and the wheel
// step through them.
BarItem {
    name: "Keyboard layout"
    tooltip: Keyboard.layout
    popup: LanguagePopup {}

    BarText {
        Layout.fillHeight: true
        text: Keyboard.short
        fontSize: Theme.languageTextSize
        // Two capitals in a row of glyphs: centred on their ink like the
        // glyphs, not on a cap height the glyphs do not have.
        opticalCentre: true
    }

    actions: ({
            [Qt.RightButton]: () => Keyboard.next()
        })

    scrolls: true
    Accessible.onScrollUpAction: scrollUp()
    Accessible.onScrollDownAction: scrollDown()
    onScrollUp: Keyboard.next()
    onScrollDown: Keyboard.prev()
}

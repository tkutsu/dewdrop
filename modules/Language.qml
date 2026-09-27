import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// custom/language
BarItem {
    tooltip: Keyboard.layout

    BarText {
        Layout.fillHeight: true
        text: Keyboard.short
        fontSize: Theme.labelSize
        // Two capitals in a row of glyphs: centred on their ink like the
        // glyphs, not on a cap height the glyphs do not have.
        opticalCentre: true
    }

    actions: ({
            [Qt.LeftButton]: () => Keyboard.next()
        })

    onScrollUp: Keyboard.prev()
    onScrollDown: Keyboard.next()
}

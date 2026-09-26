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
        // Cap-centring and the glyphs' ink-centring round in opposite
        // directions in a 25px bar, which left the label a pixel below the
        // icons it stands between. Same correction the launcher makes.
    }

    onClicked: function (mouse) {
        if (mouse.button === Qt.LeftButton)
            Keyboard.next();
    }

    onScrollUp: Keyboard.prev()
    onScrollDown: Keyboard.next()
}

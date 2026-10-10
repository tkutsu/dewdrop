import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// custom/nightmode: left click opens the brightness popup, right click
// toggles the mode, scroll steps the backlight.
BarItem {
    name: "Display"
    tooltip: NightMode.tooltip
    popup: DisplayPopup {}
    // On is a state worth seeing; off is the screen as it always is.
    quiet: !NightMode.on

    // Reserve one icon slot so the narrower dim bulb cannot resize the bar.
    Item {
        Layout.fillHeight: true
        implicitWidth: Math.max(onRuler.implicitWidth, offRuler.implicitWidth)

        Glyph {
            x: Math.round((parent.width - width) / 2)
            height: parent.height
            text: NightMode.icon
            fontSize: Theme.glyphSize - 1
            nudge: -1
        }
        Glyph {
            id: onRuler
            text: Theme.glyph.nightOn
            fontSize: Theme.glyphSize - 1
            opacity: 0
        }
        Glyph {
            id: offRuler
            text: Theme.glyph.nightOff
            fontSize: Theme.glyphSize - 1
            opacity: 0
        }
    }

    actions: ({
            [Qt.RightButton]: () => NightMode.toggle()
        })

    scrolls: true
    Accessible.onScrollUpAction: scrollUp()
    Accessible.onScrollDownAction: scrollDown()
    onScrollUp: NightMode.nudge(true)
    onScrollDown: NightMode.nudge(false)
}

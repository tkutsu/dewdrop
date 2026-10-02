import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// custom/nightmode: left click opens the brightness popup, right click
// toggles the mode, scroll steps the backlight.
BarItem {
    tooltip: NightMode.tooltip
    popup: DisplayPopup {}
    // On is a state worth seeing; off is the screen as it always is.
    quiet: !NightMode.on

    // Reserve one icon slot so the narrower dim bulb cannot resize the bar.
    Item {
        Layout.fillHeight: true
        implicitWidth: Theme.glyphSize - 2

        Glyph {
            x: Math.round((parent.width - width) / 2)
            height: parent.height
            text: NightMode.icon
            nudge: -1
        }
    }

    actions: ({
            [Qt.RightButton]: () => NightMode.toggle()
        })

    onScrollUp: NightMode.nudge(true)
    onScrollDown: NightMode.nudge(false)
}

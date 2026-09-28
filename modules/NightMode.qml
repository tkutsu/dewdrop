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

    Glyph {
        Layout.fillHeight: true
        text: NightMode.icon
    }

    actions: ({
            [Qt.RightButton]: () => NightMode.toggle()
        })

    onScrollUp: NightMode.nudge(true)
    onScrollDown: NightMode.nudge(false)
}

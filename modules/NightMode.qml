import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// custom/nightmode: click toggles the mode, scroll steps the backlight.
BarItem {
    tooltip: NightMode.tooltip
    // On is a state worth seeing; off is the screen as it always is.
    quiet: !NightMode.on

    Glyph {
        Layout.fillHeight: true
        text: NightMode.icon
    }

    onClicked: function (mouse) {
        if (mouse.button === Qt.LeftButton)
            NightMode.toggle();
    }

    onScrollUp: NightMode.nudge(true)
    onScrollDown: NightMode.nudge(false)
}

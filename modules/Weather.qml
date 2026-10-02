import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services as Services

// The strongest condition forecast in the next six hours, beside connectivity.
BarItem {
    settingsKey: "weather"
    quiet: true
    tooltip: Services.Weather.tooltip
    popup: WeatherPopup {}

    Glyph {
        Layout.fillHeight: true
        text: Services.Weather.icon
        fontSize: Theme.trayGlyphSize - 1
        nudge: -1
        opacity: Services.Weather.outlook && !Services.Weather.stale ? 1 : Theme.dimOpacity
    }
}

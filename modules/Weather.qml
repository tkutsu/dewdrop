import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services as Services

// The current hour's icon or temperature, or today's predominant daylight icon.
BarItem {
    id: root
    name: "Weather"
    settingsKey: "weather"
    quiet: true
    tooltip: Services.Weather.tooltip
    popup: WeatherPopup {}
    textPress: root.showTemperature
    shows: root.showTemperature ? temperatureText.text : ""
    Layout.rightMargin: root.showTemperature ? -2 : 0

    readonly property bool showTemperature: Settings.weatherDisplay === "temperature"
    readonly property var temperature: Services.Weather.thisHour?.[Services.Weather.feelsLike ? "feelsLike" : "temperature"]
    readonly property var forecast: Settings.weatherDisplay === "day" ? Services.Weather.today : Services.Weather.thisHour

    actions: ({
            [Qt.RightButton]: () => Services.Weather.refresh(true)
        })

    Glyph {
        Layout.fillHeight: true
        visible: !root.showTemperature
        text: root.forecast?.icon ?? "\u{f0590}"
        fontSize: Theme.trayGlyphSize - 1
        nudge: -1
        opacity: root.forecast && !Services.Weather.stale ? 1 : Theme.dimOpacity
    }

    BarText {
        id: temperatureText
        Layout.fillHeight: true
        visible: root.showTemperature
        tightWidth: true
        text: Services.Weather.formatTemperature(root.temperature, false)
        opacity: root.temperature != null && !Services.Weather.stale ? 1 : Theme.dimOpacity
    }
}

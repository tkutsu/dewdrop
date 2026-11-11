import QtQuick
import QtQuick.Layouts
import qs.src.core
import qs.src.components
import qs.src.services as Services

// A formatted weather readout, sharing the popup's forecast and temperature units.
BarItem {
    id: root
    name: "Weather"
    present: Tools.has("python3")
    settingsKey: "weather"
    quiet: true
    tooltip: Services.Weather.tooltip
    popup: WeatherPopup {}
    textPress: root.showTemperature
    shows: root.showTemperature ? Services.Weather.formatTemperature(root.temperature, false) : ""
    trimRight: Settings.weatherFormat.endsWith("{temp}") ? 3 : 1
    spacing: 0

    readonly property bool showTemperature: Settings.weatherFormat.includes("{temp}")
    readonly property var forecast: Services.Weather.barForecast
    readonly property var temperature: root.forecast?.[Services.Weather.temperatureKey]
    readonly property var parts: Settings.weatherFormat.split(/(\{icon\}|\{temp\})/).filter(part => part !== "")

    actions: ({
            [Qt.RightButton]: () => Services.Weather.refresh(true)
        })

    Repeater {
        model: root.parts
        delegate: Loader {
            required property string modelData
            Layout.fillHeight: true
            sourceComponent: modelData === "{icon}" ? sky : readout
            Component {
                id: sky
                Glyph {
                    text: root.forecast?.icon ?? "\u{f0590}"
                    fontSize: Theme.trayGlyphSize - 1
                    nudge: -1
                    opacity: root.forecast && !Services.Weather.stale ? 1 : Theme.dimOpacity
                }
            }
            Component {
                id: readout
                BarText {
                    text: modelData === "{temp}" ? Services.Weather.formatTemperature(root.temperature, false) : modelData
                    tightWidth: modelData === "{temp}"
                    opacity: root.temperature != null && !Services.Weather.stale ? 1 : Theme.dimOpacity
                }
            }
        }
    }
}

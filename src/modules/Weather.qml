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
    trimRight: root.parts[root.parts.length - 1]?.token === "{temp}" ? 3 : 1
    spacing: 0

    readonly property bool showTemperature: Settings.weatherFormat.includes("{temp}")
    readonly property var forecast: Services.Weather.barForecast
    readonly property var temperature: root.forecast?.[Services.Weather.temperatureKey]
    readonly property var parts: Settings.weatherParts

    // Raised and lowered parts, the size and places of a small AM/PM's.
    ScriptMetrics {
        id: scripts
        height: root.height
    }

    Repeater {
        model: root.parts
        delegate: Loader {
            required property var modelData
            Layout.fillHeight: true
            sourceComponent: modelData.token === "{icon}" ? sky : readout
            Component {
                id: sky
                Glyph {
                    text: root.forecast?.icon ?? "\u{f0590}"
                    // Every sky there is a drawing for, so the weather turning
                    // does not move the temperature.
                    alternates: Object.keys(Services.Weather.tints)
                    fontSize: Theme.trayGlyphSize - 1
                    nudge: -1
                    opacity: root.forecast && !Services.Weather.stale ? 1 : Theme.dimOpacity
                }
            }
            Component {
                id: readout
                BarText {
                    text: modelData.token === "{temp}" ? Services.Weather.formatTemperature(root.temperature, false) : modelData.token
                    tightWidth: modelData.token === "{temp}"
                    fontSize: modelData.shift ? scripts.smallFontSize : scripts.fontSize
                    nudge: modelData.shift ? scripts.nudge(modelData.shift) : 0
                    opacity: root.temperature != null && !Services.Weather.stale ? 1 : Theme.dimOpacity
                }
            }
        }
    }
}

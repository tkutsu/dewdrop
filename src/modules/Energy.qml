import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.src.core
import qs.src.components
import qs.src.services

// The laptop's battery in tenths, with a bolt while on the adapter, or a
// plug on a machine without one. Always out: the popup holds the energy mode
// and the idle timers, which every machine has. Right click opens
// batteryCommand (Power Statistics) where there is a battery to graph, and
// the popup otherwise.
BarItem {
    id: root
    name: Energy.battery ? "Battery" : "Energy"

    settingsKey: "energy"
    tooltip: Energy.battery ? `Battery ${Energy.summary}` : Energy.hasModes ? `Energy mode: ${Energy.modeName}` : "Energy"
    popup: EnergyPopup {}

    Glyph {
        Layout.fillHeight: true
        text: !Energy.battery ? Theme.glyph.plug
            : (Energy.plugged ? Theme.glyph.batteryCharging : Theme.glyph.battery)[Math.round(Energy.percent / 10)]
        color: Energy.low ? Theme.warn : Theme.fg
    }

    actions: ({
            [Qt.RightButton]: () => {
                const command = Energy.battery ? Settings.helper(Settings.batteryCommand, false) : [];
                if (command.length === 0)
                    return root.togglePopup();
                OpenPopup.dismiss();
                Quickshell.execDetached(command);
            }
        })
}

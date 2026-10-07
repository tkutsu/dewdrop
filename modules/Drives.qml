import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// Removable drives, and wired things with a battery, where udiskie's tray
// icon was: only on the bar while something is plugged in. The popup says how
// full each drive is and takes it out safely.
BarItem {
    id: root

    settingsKey: "drives"
    present: Drives.present
    tooltip: {
        const drives = Drives.drives;
        if (drives.length === 1)
            return drives[0].name;
        if (drives.length > 1)
            return `${drives.length} drives`;
        return Drives.batteries.map(d => `${d.model || "Battery"} ${Math.round(d.percentage * 100)}%`).join(", ");
    }
    popup: DrivesPopup {}

    Glyph {
        Layout.fillHeight: true
        text: Theme.glyph.drive
        fontSize: Theme.trayGlyphSize - 1
        nudge: -1
    }
}

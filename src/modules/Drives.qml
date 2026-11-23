import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.src.core
import qs.src.components
import qs.src.services

// Removable disks, and wired things with a battery, where udiskie's tray
// icon was: out on the bar while something is plugged in, and in the drawer
// otherwise. The popup says how full each disk is and takes it out safely;
// right click is disksCommand (Disk Utility), for formatting and the rest.
BarItem {
    id: root
    name: "Disks"

    settingsKey: "drives"
    quiet: !Drives.present
    tooltip: {
        const drives = Drives.drives;
        if (drives.length === 1)
            return drives[0].name;
        if (drives.length > 1)
            return `${drives.length} disks`;
        if (Drives.batteries.length > 0)
            return Drives.batteries.map(d => `${d.model || "Battery"} ${Math.round(d.percentage * 100)}%`).join(", ");
        return "No external disks";
    }
    popup: DrivesPopup {}

    Glyph {
        Layout.fillHeight: true
        text: Theme.glyph.drive
        fontSize: Theme.trayGlyphSize - 1
        nudge: -1
    }

    // Left is the popup (BarItem.popupButton); right is disksCommand, or the
    // popup again when that is missing, where it says so.
    actions: ({
            [Qt.RightButton]: () => {
                const command = Settings.helper(Settings.disksCommand, false);
                if (command.length === 0)
                    return root.togglePopup();
                OpenPopup.dismiss();
                Quickshell.execDetached(command);
            }
        })
}

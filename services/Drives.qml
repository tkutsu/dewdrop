pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs

// What is plugged in that can be taken out again: USB sticks, card readers,
// an e-reader, a phone that mounts as a disk. And the batteries of wired
// things that report one (a Logitech receiver's mouse, a phone UPower knows);
// the Bluetooth popup already has the wireless ones.
//
// udiskie still runs, trayless, to mount what arrives. This only reads lsblk
// and hands safe removal to udisksctl, which unmounts every filesystem on the
// drive and then powers it down, so it can be pulled out without a write cut
// short.
Singleton {
    id: root

    // [{ disk, name, size, used, total, volumes: [{ path, mounted, mountpoint }] }]
    property var drives: []
    // The disks being taken out, by path, for the row's spinner.
    property var ejecting: ({})

    readonly property var batteries: UPower.devices.values.filter(d => d.isPresent && !d.isLaptopBattery && d.type !== UPowerDeviceType.LinePower && !d.nativePath.includes("bluez"))

    readonly property bool present: drives.length > 0 || batteries.length > 0

    function eject(drive): void {
        if (root.ejecting[drive.disk])
            return;
        root.ejecting = Object.assign({}, root.ejecting, { [drive.disk]: true });
        ejector.createObject(root, { drive }).running = true;
    }

    // Into the file manager, or mounted first when nothing on it is.
    function open(drive): void {
        const mounted = drive.volumes.find(v => v.mounted);
        if (mounted)
            Quickshell.execDetached([Settings.fileManager, mounted.mountpoint]);
        else
            root.mount(drive);
    }

    // An unmounted volume on a drive that udiskie left alone (one it could
    // not mount, or one unmounted by hand).
    function mount(drive): void {
        for (const v of drive.volumes)
            if (!v.mounted)
                Quickshell.execDetached(["udisksctl", "mount", "--no-user-interaction", "-b", v.path]);
        settle.restart();
    }

    function notify(title: string, body: string): void {
        Quickshell.execDetached(["notify-send", "-a", "quickshell", "-i", "drive-removable-media", title, body]);
    }

    // Every filesystem off it, then the power: one script so that a busy
    // volume stops the power-off rather than racing it.
    Component {
        id: ejector

        Process {
            id: proc

            required property var drive

            command: ["sh", "-c", 'disk=$1; shift; for v; do udisksctl unmount --no-user-interaction -b "$v" || exit 1; done; udisksctl power-off --no-user-interaction -b "$disk"', "sh", drive.disk].concat(drive.volumes.filter(v => v.mounted).map(v => v.path))
            stderr: StdioCollector {
                id: err
            }
            onExited: function (code) {
                if (code === 0)
                    root.notify(`${proc.drive.name} can be unplugged`, "");
                else
                    root.notify(`Could not remove ${proc.drive.name}`, err.text.trim().split(": ").pop());
                const next = Object.assign({}, root.ejecting);
                delete next[proc.drive.disk];
                root.ejecting = next;
                root.refresh();
                proc.destroy();
            }
        }
    }

    function refresh(): void {
        if (!lsblk.running)
            lsblk.running = true;
    }

    Process {
        id: lsblk

        command: ["lsblk", "-J", "-b", "-o", "PATH,TYPE,TRAN,RM,HOTPLUG,SIZE,LABEL,VENDOR,MODEL,FSTYPE,FSSIZE,FSUSED,MOUNTPOINT"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.drives = root.parse(text)
        }
    }

    // A disk that can be taken out, and every filesystem on it: the disk
    // itself when it has no partition table (a Kobo, most cameras), or its
    // partitions. An empty card reader is size 0 and is left out.
    function parse(text: string): var {
        let devices;
        try {
            devices = JSON.parse(text).blockdevices;
        } catch (e) {
            return root.drives;
        }
        return devices.filter(d => d.type === "disk" && d.size > 0 && (d.tran === "usb" || d.rm || d.hotplug)).map(d => {
            const volumes = [d].concat(d.children ?? []).filter(v => v.fstype && v.fstype !== "swap");
            const mounted = volumes.filter(v => v.mountpoint);
            const label = volumes.map(v => v.label).find(l => l);
            const model = [d.vendor, d.model].filter(s => s).map(s => s.trim()).join(" ");
            return {
                disk: d.path,
                name: label || model || d.path,
                size: d.size,
                used: mounted.reduce((sum, v) => sum + (v.fsused ?? 0), 0),
                total: mounted.reduce((sum, v) => sum + (v.fssize ?? 0), 0),
                volumes: volumes.map(v => ({ path: v.path, mounted: !!v.mountpoint, mountpoint: v.mountpoint ?? "" }))
            };
        });
    }

    // A drive arriving or leaving is a block uevent; a beat after one, once
    // the partitions have turned up and udiskie has mounted them, look again.
    Process {
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=block"]
        stdout: SplitParser {
            onRead: settle.restart()
        }
    }

    Timer {
        id: settle
        interval: 800
        onTriggered: root.refresh()
    }

    // Mounting and filling a drive raise no uevent, so while one is in, the
    // figures are read again every few seconds.
    Timer {
        interval: 5000
        repeat: true
        running: root.drives.length > 0
        onTriggered: root.refresh()
    }
}

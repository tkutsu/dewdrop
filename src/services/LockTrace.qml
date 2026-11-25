pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.src.core

// Temporary: what the lock screen saw, kept in the state folder so it
// outlives the reboot that ends a stuck lock. For a lock that woke from
// sleep taking no keys (2026-11-25). Never anything that was typed.
Singleton {
    id: root

    property var lines: []

    function note(text: string): void {
        const line = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss.zzz") + " " + text;
        root.lines = root.lines.concat([line]).slice(-600);
        file.setText(root.lines.join("\n") + "\n");
    }

    FileView {
        id: file

        path: Paths.state("lock-trace.log")
        blockLoading: true
        atomicWrites: true
        printErrors: false
    }

    // Carry on from the last run's lines, so a restart keeps them.
    Component.onCompleted: {
        const old = file.text().trim();
        root.lines = old ? old.split("\n").slice(-600) : [];
        root.note("bar started");
    }

    Connections {
        target: WallClock

        function onWokeUp(): void {
            root.note("woke from sleep");
        }
    }

    Connections {
        target: Quickshell

        function onScreensChanged(): void {
            root.note("screens " + Quickshell.screens.map(s => s.name).join(","));
        }
    }
}

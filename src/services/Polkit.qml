pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Polkit

// The session's polkit agent: whatever asks for a password to act as an
// administrator (pkexec, a package manager, mounting a disk) asks here, and
// modules/AuthDialog.qml is the window it asks in, loaded by shell.qml while
// a request is up.
//
// One agent per session, so another one already running (polkit-kde, lxpolkit)
// keeps the job and this stays unregistered: nothing shows, nothing breaks.
// Requests that arrive while one is up wait their turn.
Singleton {
    id: root

    // The request being answered, or null.
    readonly property AuthFlow flow: agent.flow
    readonly property bool shown: agent.isActive
    readonly property bool registered: agent.isRegistered

    PolkitAgent {
        id: agent
    }
}

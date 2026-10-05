import QtQuick
import Quickshell.Networking as NM

// One retry per failed check, however many parallel requests failed in it.
QtObject {
    id: root

    property bool active: true
    property bool pending: false
    property int attempts: 0
    property int initialMs: 5000
    property int maximumMs: 5 * 60000
    readonly property int delayMs: Math.min(initialMs * Math.pow(2, attempts), maximumMs)

    signal triggered

    function schedule(): void {
        root.pending = true;
    }

    function cancel(): void {
        root.pending = false;
    }

    function reset(): void {
        root.cancel();
        root.attempts = 0;
    }

    // A manual retry or a known reconnect starts a fresh sequence immediately.
    function retryNow(): void {
        if (!root.active)
            return;
        root.reset();
        root.triggered();
    }

    property Timer timer: Timer {
        interval: root.delayMs
        running: root.active && root.pending
        onTriggered: {
            root.pending = false;
            root.attempts = Math.min(root.attempts + 1, 16);
            root.triggered();
        }
    }

    property Connections linkRecovery: Connections {
        target: Network
        function onOnlineChanged(): void {
            if (Network.online && root.pending)
                root.retryNow();
        }
    }

    property Connections internetRecovery: Connections {
        target: NM.Networking
        function onConnectivityChanged(): void {
            if (NM.Networking.connectivity === NM.NetworkConnectivity.Full && root.pending)
                root.retryNow();
        }
    }
}

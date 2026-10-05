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
    property double retryAt: 0
    property double clockNow: Date.now()
    readonly property int delayMs: Math.min(initialMs * Math.pow(2, attempts), maximumMs)

    signal triggered

    function schedule(): void {
        if (root.pending)
            return;
        root.clockNow = Date.now();
        root.retryAt = root.clockNow + root.delayMs;
        root.pending = true;
    }

    function cancel(): void {
        root.pending = false;
        root.retryAt = 0;
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
        interval: Math.max(1, Math.ceil(root.retryAt - root.clockNow))
        running: root.active && root.pending
        onTriggered: {
            root.clockNow = Date.now();
            if (root.clockNow < root.retryAt) {
                root.timer.restart();
                return;
            }
            root.pending = false;
            root.retryAt = 0;
            root.attempts = Math.min(root.attempts + 1, 16);
            root.triggered();
        }
    }

    property Connections wakeRecovery: Connections {
        target: WallClock
        function onWokeUp(): void {
            if (!root.active || !root.pending)
                return;
            root.clockNow = Date.now();
            if (root.clockNow >= root.retryAt)
                root.retryNow();
            else
                root.timer.restart();
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

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.src.core
import "../lib/Fuzzy.js" as Fuzzy

// A mailbox-wide address cache, scanned in bounded batches outside the UI process.
Singleton {
    id: root

    property var entries: []
    property bool loading: false
    property bool cached: false
    property bool started: false
    property bool more: true
    property int scanned: 0
    property string trouble: ""
    property int failures: 0
    property int generation: 0
    property real triedAt: 0
    readonly property int retryMs: root.failures ? Math.min(5000 * Math.pow(2, root.failures - 1), 300000) : root.more ? 250 : 60000
    readonly property var command: ["python3", Quickshell.shellPath("scripts/gmail-addresses"),
        "--cache", Paths.cache("gmail-addresses.sqlite"), "--credentials", Paths.data(Google.file)]

    // Show the saved grant's addresses first, then resume or refresh its scan.
    function ensure(): void {
        root.started = true;
        if (root.loading || !Google.configured || !Tools.has("python3"))
            return;
        if (!root.cached) {
            root.loading = true;
            saved.generation = root.generation;
            saved.running = true;
        } else if (Date.now() - root.triedAt >= (root.failures ? root.retryMs : 60000)) {
            root.sync();
        }
    }

    function sync(): void {
        if (root.loading || !Google.configured || !Tools.has("python3"))
            return;
        if (Google.needsConsent) {
            root.trouble = Google.reconnect;
            return;
        }
        root.loading = true;
        root.triedAt = Date.now();
        const generation = root.generation;
        Google.authorised(() => {
            if (generation !== root.generation)
                return;
            worker.generation = generation;
            worker.running = true;
        }, why => {
            if (generation !== root.generation)
                return;
            root.trouble = why;
            root.failures++;
            root.loading = false;
        });
    }

    function apply(text): void {
        try {
            const data = JSON.parse(text);
            if (data.busy)
                return;
            root.entries = data.entries.map(entry => Object.assign({}, entry, {
                fields: [[...Fuzzy.prep(entry.address), 1], [...Fuzzy.prep(entry.name), 0.8]]
            }));
            root.more = data.more;
            root.scanned = data.scanned;
            root.trouble = data.trouble ?? "";
            if (data.status === 401) {
                Google.accessToken = "";
                Google.tokenExpiry = 0;
            }
        } catch (error) {
            root.trouble = "Could not read the mailbox address index";
        }
    }

    Process {
        id: saved
        property int generation: 0
        command: root.command.concat(["--cached"])
        stdout: StdioCollector { id: savedOutput }
        onExited: code => {
            if (saved.generation !== root.generation)
                return;
            root.apply(savedOutput.text);
            root.cached = true;
            root.loading = false;
            root.sync();
        }
    }

    Process {
        id: worker
        property int generation: 0
        command: root.command
        environment: ({ GMAIL_TOKEN: Google.accessToken })
        stdout: StdioCollector { id: workerOutput }
        onExited: code => {
            if (worker.generation !== root.generation)
                return;
            root.apply(workerOutput.text);
            root.failures = code === 0 && !root.trouble ? 0 : root.failures + 1;
            root.loading = false;
        }
    }

    Timer {
        interval: root.retryMs
        running: root.started && root.cached && !root.loading && Google.configured && !Google.needsConsent
            && (root.more || (Launcher.shown && Launcher.mailMode))
        onTriggered: root.sync()
    }

    Connections {
        target: Google
        function onReady(): void {
            root.generation++;
            saved.running = false;
            worker.running = false;
            root.entries = [];
            root.cached = false;
            root.loading = false;
            root.more = true;
            root.scanned = 0;
            root.failures = 0;
            root.triedAt = 0;
            root.trouble = "";
            if (Launcher.shown && Launcher.mailMode)
                root.ensure();
        }
    }
}

import QtQuick
import Quickshell

// Compiles the files named in LAB_FILES (comma separated, from the config's
// root) and logs each one's result: a check for files that only build inside
// the running shell.
Item {
    required property Item backdrop
    required property Item blurred

    Component.onCompleted: {
        for (const f of (Quickshell.env("LAB_FILES") || "").split(",").filter(f => f)) {
            const c = Qt.createComponent(Qt.resolvedUrl("../" + f), Component.PreferSynchronous);
            console.log("COMPILE", f, c.status === Component.Ready ? "ok" : c.errorString());
        }
    }
}

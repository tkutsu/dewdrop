pragma Singleton

import Quickshell

// The bar's own notices. They go out through notify-send and come back in
// through the bar's notification server like any other app's, all under one
// name. `options` are notify-send's: urgency, icon, a replace hint.
Singleton {
    function send(summary: string, body: string, options: var): void {
        Quickshell.execDetached(["notify-send", "-a", "Dewdrop", ...(options ?? []), "--", summary, body]);
    }
}

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland

// A small still of a screen: a copy of it at a fraction of its size, read back
// as pixels. BackdropProbe reads how bright the screen is behind a popup off
// one.
//
// Taken here, in a window of this service's own, one at a time, for the reason
// Ink measures there: a grab parents its result to the item it grabs until it
// lands, so a grab of an item that can unload (a popup's, as it closes) frees
// the result under the render thread. Nothing here is ever unloaded. The view
// is cleared between stills instead, which drops its capture and takes a fresh
// one for the next.
Singleton {
    id: root

    // Each still asked for, answered once by the ticket take() handed out:
    // {width, height, data} with data as RGBA bytes, or null when there was
    // nothing to take.
    signal taken(int ticket, var still)

    // Quickshell 0.3.2 crashes capturing a screen that is gone, unplugged
    // mid-read, or the stand-in it keeps once the last monitor is (no name).
    function capturable(screen): bool {
        return !!screen?.name && Quickshell.screens.includes(screen);
    }

    // Ask for a still of the screen at 1/scale of its size, answered through
    // taken() and never from inside this call.
    function take(screen, scale: int): int {
        const ticket = ++root._tickets;
        root._queue.push({ticket, screen, scale});
        Qt.callLater(root._next);
        return ticket;
    }

    property int _tickets: 0
    property var _queue: []
    property var _job: null

    function _next(): void {
        if (root._job || root._queue.length === 0)
            return;
        const job = root._queue.shift();
        if (!root.capturable(job.screen)) {
            root.taken(job.ticket, null);
            Qt.callLater(root._next);
            return;
        }
        root._job = job;
        stall.restart();
        view.captureSource = job.screen;
    }

    // The job is over, with a still or without one (the screen went, the
    // grab was refused or never came back).
    function _done(still): void {
        const job = root._job;
        stall.stop();
        root._job = null;
        view.captureSource = null;
        root.taken(job.ticket, still);
        Qt.callLater(root._next);
    }

    function _grab(): void {
        const job = root._job;
        if (!job)
            return;
        canvas.width = Math.max(1, Math.round(view.width / job.scale));
        canvas.height = Math.max(1, Math.round(view.height / job.scale));
        const asked = view.grabToImage(result => {
            // A grab that outlived its job's stall timeout answers nothing.
            if (root._job !== job)
                return;
            canvas.grab = result;
            canvas.requestPaint();
        }, Qt.size(canvas.width, canvas.height));
        if (!asked)
            root._done(null);
    }

    // A frame only fails to come back if the compositor refused the capture
    // or the screen went mid-way, and one lost still must not hold up the rest.
    Timer {
        id: stall
        interval: 2000
        onTriggered: root._done(null)
    }

    // One pixel at the top-left corner, under the wallpaper, taking no clicks,
    // as Ink's meter is. What it draws is never on screen.
    PanelWindow {
        implicitWidth: 1
        implicitHeight: 1
        anchors.top: true
        anchors.left: true
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "quickshell:stills"

        // Drawn, but contributing nothing: a grab ignores the opacity above
        // what it grabs.
        Item {
            opacity: 0

            ScreencopyView {
                id: view

                width: root._job?.screen.width ?? 0
                height: root._job?.screen.height ?? 0
                live: false

                onHasContentChanged: if (hasContent && root._job)
                    Qt.callLater(root._grab)
            }

            Canvas {
                id: canvas

                property var grab: null

                // Image over FBO, and on the GUI thread: getImageData is only
                // reliable off an image target.
                renderTarget: Canvas.Image
                renderStrategy: Canvas.Immediate

                onPaint: {
                    if (!grab)
                        return;
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.drawImage(grab.url, 0, 0, width, height);
                    const data = ctx.getImageData(0, 0, width, height).data;
                    grab = null;
                    root._done({width, height, data});
                }
            }
        }
    }
}

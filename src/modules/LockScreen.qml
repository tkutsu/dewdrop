pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.src.core
import qs.src.components
import qs.src.services

// The lock screen: the session lock and, over the desktop on either side of
// it, the curtain. Lock.qml has the phases and why.
//
// The curtain is the wallpaper as the desktop frames it, faded in over the
// windows before the session locks and out after it unlocks. The lock's own
// surfaces keep that same framing, so the lock comes and goes as the glass
// alone, and the curtain under it is the same picture.
Scope {
    id: root

    readonly property int coverMs: 320
    readonly property int arriveMs: 700
    readonly property int departMs: 420

    // How the desktop has the wallpaper on this screen, from its Backdrop.
    function desktop(name: string): var {
        const backdrop = Wallpaper.backdrops[name];
        const front = backdrop?.ready ? backdrop.front : null;
        return {
            path: front ? front.path : Wallpaper.color ? "" : Wallpaper.current,
            swatch: (front ? front.swatch : Wallpaper.color) || "black",
            zoom: front?.zoom ?? 1,
            x: backdrop?.pan.fraction ?? 0.5,
            y: Wallpaper.parallaxY
        };
    }

    // Only while a lock is coming, held or going.
    LazyLoader {
        active: Lock.active

        Variants {
            model: Quickshell.screens

            PanelWindow {
                id: curtain

                required property var modelData
                screen: modelData
                readonly property var view: root.desktop(curtain.modelData.name)

                WlrLayershell.namespace: "quickshell:curtain"
                WlrLayershell.layer: WlrLayer.Overlay
                // While it covers, before the session locks, the curtain
                // takes the keys and the pointer, so nothing typed or
                // clicked reaches the windows going under it. Either side
                // of that it lets everything through.
                WlrLayershell.keyboardFocus: Lock.phase === "cover" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
                exclusionMode: ExclusionMode.Ignore
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                mask: Region {
                    item: Lock.phase === "cover" ? picture : null
                }
                color: "transparent"

                LockWallpaper {
                    id: picture

                    anchors.fill: parent
                    opacity: 0
                    path: curtain.view.path
                    swatch: curtain.view.swatch
                    zoom: curtain.view.zoom
                    decodeZoom: curtain.view.zoom
                    panX: curtain.view.x
                    panY: curtain.view.y
                    onReadyChanged: curtain.follow()
                }

                // A slow decode must not hold the lock back.
                property bool waited: false

                Timer {
                    interval: 400
                    running: true
                    onTriggered: {
                        curtain.waited = true;
                        curtain.follow();
                    }
                }

                NumberAnimation {
                    id: fadeIn
                    target: picture
                    property: "opacity"
                    to: 1
                    duration: root.coverMs
                    easing.type: Easing.InOutQuad
                    onFinished: Lock.covered()
                }

                NumberAnimation {
                    id: fadeOut
                    target: picture
                    property: "opacity"
                    to: 0
                    duration: root.coverMs
                    easing.type: Easing.InOutQuad
                    onFinished: Lock.revealed()
                }

                function follow(): void {
                    if (Lock.phase === "cover") {
                        if ((picture.ready || curtain.waited) && !fadeIn.running && picture.opacity < 1) {
                            fadeOut.stop();
                            fadeIn.start();
                        } else if (picture.opacity >= 1) {
                            Lock.covered();
                        }
                    } else if (Lock.phase === "reveal") {
                        fadeIn.stop();
                        fadeOut.start();
                    } else if (Lock.held) {
                        // Locked straight away (after a reload) or again while
                        // revealing: under the lock, where it waits to be needed.
                        fadeIn.stop();
                        fadeOut.stop();
                        picture.opacity = 1;
                    }
                }

                Component.onCompleted: curtain.follow()

                Connections {
                    target: Lock
                    function onPhaseChanged() {
                        curtain.follow();
                    }
                }
            }
        }
    }

    // The lock that never started (see the WlSessionLock below).
    Timer {
        running: Lock.held && !session.locked
        interval: 1000
        onTriggered: Lock.refused()
    }

    // Always here, never in a loader: a reload hands a held lock over to the
    // new WlSessionLock in the same place, by its id. One built afresh
    // instead leaves the old lock dead and the session locked behind
    // Hyprland's "lockscreen app died" screen.
    WlSessionLock {
        id: session

        reloadableId: "session-lock"
        locked: Lock.held

        // The compositor can refuse the lock or end it, and `locked` then
        // goes false under a held Lock; or the lock never starts, and it
        // never goes true. A moment's grace for the second, so a reload's
        // handover is never taken for a refusal.
        onLockedChanged: {
            LockTrace.note("session lock " + (session.locked ? "asked" : "dropped"));
            if (!session.locked && Lock.held)
                Lock.refused();
        }
        onSecureStateChanged: LockTrace.note("compositor " + (session.secure ? "confirmed the lock" : "released the lock"))

        WlSessionLockSurface {
            id: surface

            color: "black"
            readonly property var view: root.desktop(surface.screen?.name ?? "")

            // 0 is the desktop without the glass, 1 the lock.
            property real presence: 0

            function follow(): void {
                if (Lock.phase === "leave") {
                    arrive.stop();
                    depart.start();
                } else if (Lock.phase === "locked" && surface.presence < 1 && !arrive.running) {
                    depart.stop();
                    arrive.start();
                }
            }

            Component.onCompleted: {
                LockTrace.note("surface made on " + (surface.screen?.name ?? "no screen"));
                surface.follow();
            }
            Component.onDestruction: LockTrace.note("surface gone")
            onScreenChanged: LockTrace.note("surface moved to " + (surface.screen?.name ?? "no screen"))
            onVisibleChanged: LockTrace.note("surface " + (surface.visible ? "shown" : "hidden"))

            Connections {
                target: Lock
                function onPhaseChanged() {
                    surface.follow();
                }
            }

            NumberAnimation {
                id: arrive
                target: surface
                property: "presence"
                to: 1
                duration: root.arriveMs
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                id: depart
                target: surface
                property: "presence"
                to: 0
                duration: root.departMs
                easing.type: Easing.InOutCubic
                onFinished: Lock.left()
            }

            LockWallpaper {
                id: scene

                anchors.fill: parent
                path: surface.view.path
                swatch: surface.view.swatch
                zoom: surface.view.zoom
                decodeZoom: surface.view.zoom
                panX: surface.view.x
                panY: surface.view.y
            }

            LockPanel {
                anchors.centerIn: parent
                backdrop: scene
                presence: surface.presence
            }

            // Sleep, Restart and Shut Down, at the foot. Only
            // while locked: not as the glass goes.
            LockPower {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 56
                visible: Settings.lockPower
                enabled: Lock.phase === "locked"
                opacity: surface.presence
            }

            // Every key comes here, whichever screen has the keyboard: the
            // password is one, shared by every screen's field.
            Item {
                id: keys

                anchors.fill: parent
                focus: true

                // Temporary trace (LockTrace): whether the keyboard reaches
                // the lock, at most one line every two seconds, no key named.
                property double traced: 0
                onActiveFocusChanged: LockTrace.note("keyboard " + (keys.activeFocus ? "on" : "off") + " the lock on " + (surface.screen?.name ?? "no screen"))

                // Shift as held: its own press and release, and with any
                // other key, whatever the modifiers say, in case a release
                // went to another window before the lock.
                Keys.onReleased: event => {
                    Lock.shift = event.key !== Qt.Key_Shift && !!(event.modifiers & Qt.ShiftModifier);
                }
                Keys.onPressed: event => {
                    event.accepted = true;
                    if (Date.now() - keys.traced > 2000) {
                        keys.traced = Date.now();
                        LockTrace.note("keys arriving on " + (surface.screen?.name ?? "no screen"));
                    }
                    Lock.shift = event.key === Qt.Key_Shift || !!(event.modifiers & Qt.ShiftModifier);
                    const command = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
                    switch (event.key) {
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        Lock.submit();
                        return;
                    case Qt.Key_Backspace:
                        if (event.modifiers & Qt.ControlModifier)
                            Lock.clear();
                        else
                            Lock.erase();
                        return;
                    case Qt.Key_Escape:
                        Lock.clear();
                        return;
                    case Qt.Key_CapsLock:
                        Lock.capsLock = !Lock.capsLock;
                        return;
                    case Qt.Key_U:
                        if (event.modifiers & Qt.ControlModifier) {
                            Lock.clear();
                            return;
                        }
                    }
                    if (command || !event.text || event.text.charCodeAt(0) < 32 || event.text === "\u007f")
                        return;
                    // Caps Lock, read off what a letter came out as: upper
                    // case without Shift, or lower with it.
                    const letter = event.text.toLowerCase() !== event.text.toUpperCase();
                    if (letter)
                        Lock.capsLock = (event.text === event.text.toUpperCase()) !== !!(event.modifiers & Qt.ShiftModifier);
                    Lock.type(event.text);
                }
            }
        }
    }
}

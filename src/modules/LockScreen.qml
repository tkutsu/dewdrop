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
// surfaces start from that same framing, so the lock comes in as the glass
// alone, while the picture zooms a touch and drifts to follow the pointer;
// leaving, it drifts back first, and the curtain under it is the same picture.
Scope {
    id: root

    // Lock Screen > Parallax, which Reduce Motion overrides.
    readonly property bool parallax: Settings.lockParallax && !Theme.reduceMotion
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

    // The zoom the lock settles at: room to drift, the wallpaper's own
    // parallax zoom if it has one.
    function lockZoom(view: var): real {
        if (!root.parallax || !view.path)
            return view.zoom;
        return Math.max(view.zoom, Settings.wallpaperParallaxZoom > 1 ? Settings.wallpaperParallaxZoom : 1.08);
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
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                exclusionMode: ExclusionMode.Ignore
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                mask: Region {}
                color: "transparent"

                LockWallpaper {
                    id: picture

                    anchors.fill: parent
                    opacity: 0
                    path: curtain.view.path
                    swatch: curtain.view.swatch
                    zoom: curtain.view.zoom
                    decodeZoom: root.lockZoom(curtain.view)
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

    // Always here, never in a loader: a reload hands a held lock over to the
    // new WlSessionLock in the same place, by its id. One built afresh
    // instead leaves the old lock dead and the session locked behind
    // Hyprland's "lockscreen app died" screen.
    WlSessionLock {
        reloadableId: "session-lock"
        locked: Lock.held

        WlSessionLockSurface {
            id: surface

            color: "black"
            readonly property var view: root.desktop(surface.screen?.name ?? "")
            readonly property real lockZoom: root.lockZoom(surface.view)

            // 0 is the desktop's framing without the glass, 1 the lock.
            property real presence: 0

            // Where the pointer points, from 0 to 1 across the screen, and
            // the crop easing after it.
            property real aimX: 0.5
            property real aimY: 0.5
            property real panX: 0.5
            property real panY: 0.5
            property bool aimed: false

            function follow(): void {
                if (Lock.phase === "leave") {
                    arrive.stop();
                    depart.start();
                } else if (Lock.phase === "locked" && surface.presence < 1 && !arrive.running) {
                    depart.stop();
                    arrive.start();
                }
            }

            // Until the pointer moves, the crop stays where the desktop had it.
            Component.onCompleted: {
                surface.aimX = surface.panX = surface.view.x;
                surface.aimY = surface.panY = surface.view.y;
                surface.follow();
            }

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

            // Ease towards the aim, only while there is somewhere to go.
            FrameAnimation {
                running: Math.abs(surface.panX - surface.aimX) > 0.0005 || Math.abs(surface.panY - surface.aimY) > 0.0005
                onTriggered: {
                    const k = 1 - Math.exp(-frameTime * 3.5);
                    surface.panX += (surface.aimX - surface.panX) * k;
                    surface.panY += (surface.aimY - surface.panY) * k;
                }
            }

            LockWallpaper {
                id: scene

                anchors.fill: parent
                path: surface.view.path
                swatch: surface.view.swatch
                decodeZoom: surface.lockZoom
                zoom: surface.view.zoom + (surface.lockZoom - surface.view.zoom) * surface.presence
                panX: surface.view.x + ((root.parallax ? surface.panX : surface.view.x) - surface.view.x) * surface.presence
                panY: surface.view.y + ((root.parallax ? surface.panY : surface.view.y) - surface.view.y) * surface.presence
            }

            HoverHandler {
                onPointChanged: {
                    if (!root.parallax || !point.position)
                        return;
                    surface.aimX = Math.max(0, Math.min(1, point.position.x / surface.width));
                    surface.aimY = Math.max(0, Math.min(1, point.position.y / surface.height));
                }
            }

            LockPanel {
                anchors.centerIn: parent
                backdrop: scene
                presence: surface.presence
            }

            // The keyboard layout, in the corner where a Mac's lock screen
            // keeps its input menu, and only with more than one to choose
            // from. A click moves to the next.
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 20
                visible: Keyboard.layouts.length > 1
                opacity: surface.presence
                width: layout.implicitWidth + 20
                height: 28
                radius: height / 2
                color: switcher.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0)

                Row {
                    id: layout

                    anchors.centerIn: parent
                    spacing: 6

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.glyph.keyboard
                        fontSize: Theme.popupGlyphSize
                        color: Theme.fg
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Keyboard.short
                        color: Theme.fg
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.popupTextSize
                        font.weight: Font.DemiBold
                    }
                }

                HoverHandler {
                    id: switcher
                }
                TapHandler {
                    onTapped: Keyboard.next()
                }
            }

            // Every key comes here, whichever screen has the keyboard: the
            // password is one, shared by every screen's field.
            Item {
                anchors.fill: parent
                focus: true

                Keys.onPressed: event => {
                    event.accepted = true;
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

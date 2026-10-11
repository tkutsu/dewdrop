pragma Singleton

import QtQuick
import Quickshell

// The pointer's light on the bar's glass (reel 10): where the pointer is over
// a bar, eased every frame towards it so the light glides rather than jumps,
// and how present it is, coming up as the pointer reaches the bar and going
// as it leaves. The shell only hears of the pointer while it is over a bar,
// so that is where the light is. Each piece of glass in that window draws it
// (Liquid.qml): the bevel round its rim catches it, and the glass glows a
// little under the pointer. Kept by Bar.qml.
Singleton {
    id: root

    property var window: null
    property bool over: false
    // Where the pointer is, in the window's pixels.
    property point target: Qt.point(0, 0)

    // Where the light is, and how much of it there is, 0..1.
    property real x: 0
    property real y: 0
    property real presence: 0

    function track(win: var, at: point): void {
        if (root.window !== win) {
            // A new window: the light starts where the pointer is.
            root.window = win;
            root.x = at.x;
            root.y = at.y;
        }
        root.target = at;
        root.over = true;
    }

    function leave(win: var): void {
        if (root.window === win)
            root.over = false;
    }

    FrameAnimation {
        running: root.over || root.presence > 0.001
        onTriggered: {
            // Exponential easing, the way a critically damped spring settles:
            // 60 ms behind the pointer, 160 ms to come up or go.
            const follow = 1 - Math.exp(-frameTime / 0.06);
            const fade = 1 - Math.exp(-frameTime / 0.16);
            root.x += (root.target.x - root.x) * follow;
            root.y += (root.target.y - root.y) * follow;
            root.presence += ((root.over ? 1 : 0) - root.presence) * fade;
            if (!root.over && root.presence < 0.001)
                root.presence = 0;
        }
    }
}

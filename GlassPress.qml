pragma Singleton

import QtQuick
import Quickshell
import qs

// The press the bar's glass answers: one at a time, the last one made. Where
// it landed and the icon it landed on, in its window's pixels, and how far
// the glass has taken it: `lit` comes up at once and goes slowly, `pop` is a
// gel spring that runs past on the way back. Every piece of glass in that
// window reads this and draws the press if it landed on it (Liquid.qml): the
// glass lights from where the press landed.
//
// A press is made and let go by PressGlass, which every pressable icon in the
// bar has.
Singleton {
    id: root

    property Item item: null
    property var window: null
    property point at: Qt.point(0, 0)
    property rect box: Qt.rect(0, 0, 0, 0)
    property bool down: false

    // Under Reduce motion the glass still lights, but the icon does not pop.
    readonly property bool pops: !Theme.reduceMotion
    readonly property real iconLift: 0.08
    readonly property real dentSpread: Settings.pillPressStyle === "cushion" ? 160 : Settings.pillPressStyle === "deep" ? 150 : 115
    readonly property real dentDepth: Settings.pillPressStyle === "cushion" ? 0.07 : Settings.pillPressStyle === "deep" ? 0.24 : 0.18
    property real dent: 0

    NumberAnimation {
        id: indent
        target: root; property: "dent"; to: 1; duration: 160; easing.type: Easing.InOutCubic
        onFinished: if (!root.down) recover.start()
    }
    NumberAnimation {
        id: recover
        target: root; property: "dent"; to: 0; duration: 310
        easing.type: Easing.OutBack; easing.overshoot: 0.6
    }

    property real lit: down ? 1 : 0
    Behavior on lit {
        NumberAnimation {
            duration: root.down ? 80 : 450
            easing.type: root.down ? Easing.OutQuad : Easing.OutCubic
        }
    }
    property real pop: down ? 1 : 0
    Behavior on pop {
        SpringAnimation {
            spring: 5
            damping: 0.26
            epsilon: 0.002
        }
    }

    // A press on `icon`, landing `at` in its window's pixels.
    function press(icon: Item, at: point): void {
        const win = icon.QsWindow.window;
        if (!win)
            return;
        root.item = icon;
        root.window = win;
        root.at = at;
        const corner = icon.mapToItem(null, 0, 0);
        root.box = Qt.rect(corner.x, corner.y, icon.width, icon.height);
        root.down = true;
        if (Settings.pillPressMorph && !Theme.reduceMotion) {
            recover.stop();
            indent.restart();
        }
    }

    function release(icon: Item): void {
        if (icon === root.item) {
            root.down = false;
            if (!indent.running)
                recover.restart();
        }
    }

    // How far `icon` is popped: the press's spring if it is the icon
    // pressed last, otherwise nothing.
    function popOf(icon: Item): real {
        return root.pops && !Settings.pillPressMorph && icon === root.item ? root.pop : 0;
    }
}

import QtQuick
import QtQuick.Effects
import qs

// Roll a whole icon with RollingText's spring, scale and focus, including SVGs.
Item {
    id: root

    property string text: ""
    property int fontSize: Theme.glyphSize
    property color color: Theme.fg
    property bool animate: true
    readonly property bool rolling: roll.running
    property bool ready: false
    property string shown: ""
    property string was: ""
    property real s: 1.45
    readonly property bool reduceMotion: Theme.reduceMotion
    readonly property real b: rolling ? root.damped(s, 0.54, 1) : 1
    readonly property real g: rolling ? root.damped(s, 1, 0.65) : 1
    readonly property real f: rolling ? root.damped(s, 0.85, 0.74) : 1
    readonly property real o: rolling ? root.damped(s, 1, 0.46) : 1
    readonly property real travel: -0.34 * metrics.height

    implicitWidth: fontSize
    implicitHeight: Theme.barHeight
    clip: true

    FontMetrics {
        id: metrics
        font.family: Theme.bodyFont
        font.pixelSize: root.fontSize
        font.weight: Theme.bodyWeight
    }

    // Same damped step response as RollingText, in multiples of Theme.rollMs.
    function damped(t, zeta, settle) {
        if (t <= 0)
            return 0;
        if (zeta >= 0.999) {
            const k = 5.83 / settle;
            return 1 - (1 + k * t) * Math.exp(-k * t);
        }
        const omega = 4 / (zeta * settle);
        const k = zeta * omega;
        const wd = omega * Math.sqrt(1 - zeta * zeta);
        return 1 - Math.exp(-k * t) * (Math.cos(wd * t) + (k / wd) * Math.sin(wd * t));
    }

    // Hidden icons and reduced motion swap immediately; fresh mounts start still.
    function settle() {
        debounce.stop();
        roll.stop();
        root.shown = root.text;
        root.was = "";
    }

    function change() {
        if (!root.ready || !root.animate || !root.visible || root.reduceMotion) {
            root.settle();
            return;
        }
        if (root.text === root.shown)
            return;
        root.was = root.shown;
        root.shown = root.text;
        roll.restart();
    }

    // Keep the current icon through short-lived inferred modes while typing.
    onTextChanged: {
        if (!ready || !animate || !visible)
            settle();
        else if (text === shown)
            debounce.stop();
        else
            debounce.restart();
    }
    onAnimateChanged: if (!animate) settle()
    onVisibleChanged: if (!visible) settle()
    onReduceMotionChanged: if (reduceMotion) settle()
    Component.onCompleted: {
        root.settle();
        root.ready = true;
    }

    Timer {
        id: debounce
        interval: 150
        onTriggered: root.change()
    }

    NumberAnimation {
        id: roll
        target: root
        property: "s"
        from: 0
        to: 1.45
        duration: Theme.rollMs * 1.45
    }

    Glyph {
        id: now
        width: root.width
        height: root.height
        text: root.shown
        fontSize: root.fontSize
        color: root.color
        y: -root.travel * (1 - root.b)
        scale: 0.4 + 0.6 * root.g
        opacity: root.g
        readonly property real blur: 1 - root.f
        layer.enabled: blur > 0.02
        layer.smooth: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: Math.ceil(0.04 * metrics.height * 2)
            blur: now.blur
        }
    }

    Glyph {
        id: old
        width: root.width
        height: root.height
        text: root.was
        fontSize: root.fontSize
        color: root.color
        visible: root.rolling
        y: root.travel * root.b
        scale: 1 - 0.6 * root.g
        opacity: 1 - root.g
        layer.enabled: visible && root.o > 0.02
        layer.smooth: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: Math.ceil(0.04 * metrics.height * 2)
            blur: root.o
        }
    }
}

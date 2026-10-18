import QtQuick

// Both icon copies follow one path and crossfade at the same position.
QtObject {
    required property Item source
    property Item target: null
    property real reveal: 1
    property real restingX: 0
    readonly property real phase: Math.max(0, Math.min(1, (0.38 - reveal) / 0.18))
    readonly property real progress: phase * phase * (3 - 2 * phase)
    readonly property real distance: {
        if (!target)
            return restingX;
        let x = 0;
        for (let item = target; item; item = item.parent)
            x += item.x;
        for (let item = source; item; item = item.parent)
            x -= item.x;
        return x;
    }
    readonly property real sourceX: restingX + (distance - restingX) * progress
    readonly property real targetX: (restingX - distance) * (1 - progress)
}

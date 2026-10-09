import QtQuick
import qs

// A number between `from` and `to`, in `step`s, with its value read out
// beside the track. The value follows the drag at once, but is only written
// once the drag rests: every write is a whole settings.json and a reload of
// whatever reads it.
Row {
    id: root

    property var setting: null
    readonly property real from: root.setting?.from ?? 0
    readonly property real to: root.setting?.to ?? 1
    readonly property real step: root.setting?.step ?? 0.01

    // The value while it is being dragged, NaN otherwise.
    property real draft: NaN
    readonly property real value: isNaN(root.draft) ? Number(root.setting?.get() ?? root.from) : root.draft

    spacing: 10

    function snap(v: real): real {
        const snapped = root.from + Math.round((v - root.from) / root.step) * root.step;
        return Math.max(root.from, Math.min(root.to, Number(snapped.toFixed(6))));
    }

    PopupText {
        anchors.verticalCenter: parent.verticalCenter
        width: 40
        horizontalAlignment: Text.AlignRight
        text: root.setting?.format ? root.setting.format(root.value) : String(root.value)
        color: Theme.label2
        font.pixelSize: Theme.captionSize
    }

    Slider {
        name: root.setting?.title ?? ""
        anchors.verticalCenter: parent.verticalCenter
        width: 140
        value: (root.value - root.from) / (root.to - root.from)
        wheelStep: root.step / (root.to - root.from)
        onMoved: function (v) {
            root.draft = root.snap(root.from + v * (root.to - root.from));
            commit.restart();
        }
    }

    Timer {
        id: commit

        interval: 400
        onTriggered: {
            if (root.draft !== Number(root.setting.get()))
                root.setting.set(root.draft);
            root.draft = NaN;
        }
    }
}

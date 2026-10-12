import QtQuick
import qs
import qs.components

// The real Slider in the sound popup's frost, taking real input: the lab's
// window takes the pointer in this scene, so a synthetic drag can hold it.
Item {
    id: scene

    required property Item backdrop
    required property Item blurred


    ShaderEffect {
        anchors.fill: parent

        property var blurred: scene.blurred
        readonly property size size: Qt.size(width, height)
        readonly property vector4d box: Qt.vector4d(20, 20, scene.width - 40, scene.height - 40)
        readonly property real radius: Theme.popupRadius
        readonly property vector4d fill: Qt.vector4d(Theme.popupBg.r, Theme.popupBg.g, Theme.popupBg.b, Theme.popupBg.a)
        readonly property real lit: 0

        fragmentShader: Qt.resolvedUrl("frost.frag.qsb")
    }

    Text {
        x: 40
        y: 36
        text: "real Slider"
        color: Theme.label2
        font.family: Settings.font
        font.pixelSize: 12
    }

    Slider {
        id: slider
        x: 40
        y: 70
        width: 300
        value: 0.3
        onMoved: v => {
            console.log("LAB moved", v.toFixed(3));
            slider.value = v;
        }
    }
}

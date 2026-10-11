import QtQuick
import qs
import qs.components

// ScrollEdges on a list scrolling down and back, with no fade on the left for
// comparison. Also compiles every file that took ScrollEdges and logs what
// fails, since most of them only build inside a popup.
Item {
    id: scene

    required property Item backdrop
    required property Item blurred

    property real scroll: 0

    SequentialAnimation {
        running: true
        loops: Animation.Infinite

        PauseAnimation { duration: 600 }
        NumberAnimation { target: scene; property: "scroll"; to: 1; duration: 2000; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 600 }
        NumberAnimation { target: scene; property: "scroll"; to: 0; duration: 1600; easing.type: Easing.InOutSine }
    }

    Component.onCompleted: {
        for (const f of ["components/EmailPopup.qml", "components/FilePreview.qml", "components/MusicPopup.qml", "components/NotificationsPopup.qml", "components/WallpaperPopup.qml", "modules/LauncherMenu.qml", "modules/SettingsMenu.qml"]) {
            const c = Qt.createComponent(Qt.resolvedUrl("../" + f), Component.PreferSynchronous);
            console.log("COMPILE", f, c.status === Component.Ready ? "ok" : c.errorString());
        }
    }

    // The sound popup's frost.
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

    Rim {
        x: 20
        y: 20
        width: scene.width - 40
        height: scene.height - 40
        radius: Theme.popupRadius
    }

    Row {
        x: 32
        y: 32
        spacing: 24

        Repeater {
            model: [false, true]

            Column {
                id: side

                required property bool modelData
                spacing: 8

                Text {
                    text: side.modelData ? "ScrollEdges" : "today: cut off"
                    color: Theme.label
                    font.family: Settings.font
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    width: 220
                    height: 1
                    color: Theme.stroke
                }

                ListView {
                    id: list

                    width: 220
                    height: 170
                    clip: true
                    interactive: false
                    model: 30
                    contentY: scene.scroll * (contentHeight - height)
                    layer.enabled: side.modelData && contentHeight > height
                    layer.effect: ScrollEdges {
                        view: list
                    }

                    delegate: Text {
                        required property int index
                        height: 24
                        verticalAlignment: Text.AlignVCenter
                        text: ["Speakers", "Headphones", "HDMI", "Bluetooth", "USB DAC"][index % 5] + " " + (index + 1)
                        color: index % 3 ? Theme.label2 : Theme.label
                        font.family: Settings.font
                        font.pixelSize: Theme.textSize
                    }
                }
            }
        }
    }
}

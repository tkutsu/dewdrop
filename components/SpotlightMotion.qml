import QtQuick
import qs

// Spotlight's width, opacity and defocus curve, shared by launcher and settings.
QtObject {
    id: root
    required property bool opened
    required property int dismissMs
    property real widthRatio: 1012 / 960
    property real contentAlpha: 0
    property real exitBlur: 0

    onOpenedChanged: {
        entrance.stop();
        dismissal.stop();
        if (Theme.reduceMotion) {
            root.widthRatio = 1;
            root.contentAlpha = root.opened ? 1 : 0;
            root.exitBlur = 0;
        } else if (root.opened) {
            entrance.start();
        } else {
            dismissal.start();
        }
    }

    property ParallelAnimation entrance: ParallelAnimation {
        id: entrance
        SequentialAnimation {
            PauseAnimation { duration: 33 }
            NumberAnimation { target: root; property: "widthRatio"; to: 976 / 960; duration: 33 }
            NumberAnimation { target: root; property: "widthRatio"; to: 955 / 960; duration: 33 }
            NumberAnimation { target: root; property: "widthRatio"; to: 948 / 960; duration: 33 }
            NumberAnimation { target: root; property: "widthRatio"; to: 950 / 960; duration: 33 }
            NumberAnimation { target: root; property: "widthRatio"; to: 954 / 960; duration: 33 }
            NumberAnimation { target: root; property: "widthRatio"; to: 958 / 960; duration: 33 }
            NumberAnimation { target: root; property: "widthRatio"; to: 1; duration: 33 }
            PauseAnimation { duration: 69 }
        }
        NumberAnimation { target: root; property: "contentAlpha"; to: 1; duration: 67 }
        NumberAnimation { target: root; property: "exitBlur"; to: 0; duration: 67 }
    }

    property ParallelAnimation dismissal: ParallelAnimation {
        id: dismissal
        NumberAnimation { target: root; property: "widthRatio"; to: 1.03; duration: root.dismissMs; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "contentAlpha"; to: 0; duration: root.dismissMs; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "exitBlur"; to: 1; duration: root.dismissMs; easing.type: Easing.InCubic }
    }

}

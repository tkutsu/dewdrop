import QtQuick
import QtQuick.Layouts
import qs

// A previous/next control whose room folds away while its glyph stays beside the title.
Item {
    id: root
    required property bool open
    required property bool settled
    property bool previous: false
    readonly property bool animating: fold.running
    readonly property real full: icon.implicitWidth + Theme.mediaGap
    signal triggered

    Layout.fillHeight: true
    implicitWidth: root.open ? root.full : 0
    clip: width < root.full
    opacity: width / root.full
    Behavior on implicitWidth {
        enabled: root.settled
        NumberAnimation { id: fold; duration: Theme.foldMs; easing.type: Easing.InOutCubic }
    }
    Glyph {
        id: icon
        readonly property bool inkLit: true
        x: root.previous ? root.width - Theme.mediaGap - width : 0
        height: parent.height
        text: root.previous ? Theme.glyph.mediaPrev : Theme.glyph.mediaNext
        scale: press.scale
        PressGlass { id: press; icon: icon; area: tap }
        Accessible.role: Accessible.Button
        Accessible.name: root.previous ? "Previous track" : "Next track"
        Accessible.onPressAction: if (tap.enabled && enabled && visible) root.triggered()
        TapHandler {
            id: tap
            enabled: root.open
            margin: Theme.pressDip
            onTapped: root.triggered()
        }
    }
}

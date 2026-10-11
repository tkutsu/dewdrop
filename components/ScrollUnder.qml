import QtQuick
import QtQuick.Effects
import qs

// A popup's list that runs on under its header rather than stopping at it
// (reel 7): rows scrolled up past the list's top go on under the header,
// blurred, dimmed so the header reads over them, and bent up into it at its
// edge (shaders/under.frag). The header's band reaches the box's edges and
// top, not just the padding, and the list's foot fades while there is more
// below it.
//
// Put it inside the list with the list as its parent, and raise the header
// over the list (z: 1):
//
//     ListView {
//         id: list
//         clip: true
//         ScrollUnder {
//             parent: list
//             view: list
//             box: root.chromeItem
//         }
//     }
//
// The list keeps its clip, so a row under the header takes no pointer; only
// its drawing goes on, taken from the list's contents directly, which a clip
// on the list does not cut. While the list has nothing to scroll it draws as
// it always did.
Item {
    id: root

    required property Flickable view
    // The popup's box (Popup.chromeItem).
    required property Item box

    readonly property bool active: view.contentHeight + view.topMargin + view.bottomMargin > view.height + 1

    // Where the list is in the box. Walked up the parent chain rather than
    // handed to mapToItem, which would leave the binding nothing to re-run on
    // (see Liquid.windowPos).
    readonly property point at: {
        let x = 0, y = 0;
        for (let item = view; item && item !== box; item = item.parent) {
            x += item.x;
            y += item.y;
        }
        return Qt.point(x, y);
    }

    // From the box's top left down to the list's foot, across the box.
    x: -at.x
    y: -at.y
    width: box.width
    height: at.y + view.height
    z: 1
    visible: active

    ShaderEffectSource {
        id: sharp

        sourceItem: root.view.contentItem
        hideSource: root.active
        live: root.active
        sourceRect: Qt.rect(-root.view.contentItem.x - root.at.x, -root.view.contentItem.y - root.at.y, root.width, root.height)
        visible: false
    }

    MultiEffect {
        id: blur

        width: root.width
        height: root.height
        source: sharp
        blurEnabled: true
        blur: 1
        blurMax: 28
        autoPaddingEnabled: false
        visible: false
    }

    ShaderEffectSource {
        id: blurred

        sourceItem: blur
        live: root.active
        visible: false
    }

    ShaderEffect {
        anchors.fill: parent

        property var sharp: sharp
        property var blurred: blurred
        readonly property size size: Qt.size(width, height)
        readonly property real edge: root.at.y
        readonly property real soft: 6
        readonly property real bend: 14
        readonly property real reach: 20
        readonly property real steep: 2
        readonly property real through: 0.65
        // As ScrollEdges does it: the foot fades only while there is more
        // below, and in step with how much.
        readonly property real fadeBottom: Math.min(Theme.scrollEdge, Math.max(0, root.view.originY + root.view.contentHeight + root.view.bottomMargin - root.view.height - root.view.contentY))
        readonly property real boxHeight: root.box.height
        readonly property real radius: root.box.radius

        fragmentShader: Qt.resolvedUrl("../shaders/under.frag.qsb")
    }
}

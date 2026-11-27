import QtQuick
import Quickshell
import qs.src.core

// A row in a popup's list: the rounded fill that lights under the pointer, and
// the tap on the row when the row is itself a thing to press. The contents are
// laid out by whoever uses it; this is only the surface they stand on.
//
// A PopupButton on the row takes its own press, so a tap here is a tap on the
// row and nothing else.
Item {
    id: root

    default property alias content: body.data
    property string name: ""

    Accessible.role: Accessible.Button
    Accessible.name: root.name
    Accessible.ignored: root.name === "" || root.opacity <= 0
    Accessible.onPressAction: if (root.enabled && root.visible && !root.Accessible.ignored)
        root.tapped()

    // Reached by the keys (Popup.qml), which hold the selection until the
    // pointer moves again.
    property bool keyed: false
    // The popup's ChoiceBlink (Popup.choice), which the row lights with
    // while its choice flashes.
    property var blink: QsWindow.window?.choice ?? null
    property bool chosen: root.blink?.item === root
    property bool blinkOn: root.blink?.lit ?? true
    readonly property var keyPress: root.name !== "" ? () => root.tapped() : null
    readonly property Item keyItem: QsWindow.window?.keyItem ?? null
    // Whether the fill is lit: under the pointer, or the keys on the row.
    readonly property bool lit: root.chosen ? root.blinkOn : root.keyItem ? root.keyed : hover.hovered
    // Whether the row is in use: lit, or the keys on a button in it. Read by
    // the rows that show their buttons only then, so a button the keys move
    // onto stays out, lit alone.
    readonly property bool hovered: root.lit || root.keyItem !== null && root.holds(root.keyItem)

    function holds(item: Item): bool {
        for (let p = item; p; p = p.parent)
            if (p === root)
                return true;
        return false;
    }
    // Lit whatever the pointer does, while a gesture on the row has it (a
    // mail being swiped), so the row stays the selected one when the pointer
    // runs out of the popup.
    property bool held: false
    // Cards can draw their own surface while sharing the row's input.
    property bool showHighlight: true
    // How far the fill is slid sideways with the contents (a swipe), leaving
    // the popup's own background where it was.
    property real slide: 0

    // Inside a Flickable the press has to stay grabbable by the flick, so the
    // default policy is kept there; a row in a fixed list can ask for the
    // stricter one, which does not count a press that slid off it.
    property bool acceptsTap: true
    property int gesturePolicy: TapHandler.DragThreshold

    signal tapped

    HoverHandler {
        id: hover
    }

    TapHandler {
        id: tap
        enabled: root.acceptsTap
        gesturePolicy: root.gesturePolicy
        onTapped: root.tapped()
    }

    PressGlass {
        id: press
        icon: body
        area: tap
        textPress: true
        down: root.name !== "" && tap.pressed
    }

    Item {
        id: body
        anchors.fill: parent
        // Keep the hit area fixed while the selection and contents press in.
        scale: press.scale

        Rectangle {
            visible: root.showHighlight
            x: root.slide
            width: parent.width
            height: parent.height
            radius: Theme.selectionRadius
            color: root.name !== "" && (root.lit || root.held) ? Theme.selection : "transparent"
        }
    }
}

import QtQuick
import Quickshell
import qs

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
    Accessible.ignored: root.name === ""
    Accessible.onPressAction: if (root.enabled && root.visible)
        root.tapped()

    // Whether the row is lit: under the pointer, or reached by the keys
    // (Popup.qml), which hold the selection until the pointer moves again.
    // Read by the rows that show their buttons only when lit, so the keys
    // bring those out too.
    property bool keyed: false
    readonly property var keyPress: root.name !== "" ? () => root.tapped() : null
    readonly property bool hovered: QsWindow.window?.keyItem ? root.keyed : hover.hovered

    // Inside a Flickable the press has to stay grabbable by the flick, so the
    // default policy is kept there; a row in a fixed list can ask for the
    // stricter one, which does not count a press that slid off it.
    property int gesturePolicy: TapHandler.DragThreshold

    signal tapped

    Rectangle {
        anchors.fill: parent
        radius: Theme.selectionRadius
        color: root.hovered ? Theme.selection : "transparent"
    }

    HoverHandler {
        id: hover
    }

    TapHandler {
        gesturePolicy: root.gesturePolicy
        onTapped: root.tapped()
    }

    Item {
        id: body
        anchors.fill: parent
    }
}

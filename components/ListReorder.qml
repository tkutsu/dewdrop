import QtQuick
import QtQuick.Effects
import qs

// A held row stays above the view while siblings make room for its landing.
Item {
    id: root

    required property var view
    required property var model
    required property real rowHeight
    property real rightGuard: 0
    property Component lifted: null
    property var canNest: null
    property var canLift: null
    property var canHold: null
    property var heldModel: null
    property bool allowSingle: false
    property var queue: []
    property bool dragging: false
    property bool settling: false
    readonly property bool showing: dragging || settling
    property real elevation: 0
    property real dropY: 0
    property int from: -1
    property int to: -1
    property int onto: -1
    property real grabOffset: 0
    property real holdTop: 0
    property var pressedModel: null
    readonly property real liftedY: Math.max(0, Math.min(height - rowHeight, pointer.mouseY - grabOffset))
    readonly property int scrollDirection: !dragging ? 0 : pointer.mouseY < rowHeight ? -1 : pointer.mouseY > height - rowHeight ? 1 : 0
    readonly property bool dropRunning: drop.running

    signal moved(int from, int to)
    signal nested(int from, int onto)
    signal clicked(int index)
    signal held()

    function updateTarget() {
        if (!dragging)
            return;

        const centre = view.contentY + liftedY + rowHeight / 2;
        const index = view.indexAt(1, centre);
        to = index < 0 ? (centre < view.originY ? 0 : queue.length - 1) : index;
        const item = view.itemAtIndex(to);
        const fraction = item ? (centre - item.y) / item.height : 0;
        onto = canNest && fraction >= 1 / 3 && fraction <= 2 / 3 && canNest(from, to) ? to : -1;
    }

    function shift(index) {
        if (!showing || onto >= 0)
            return 0;

        return index > from && index <= to ? -rowHeight : index < from && index >= to ? rowHeight : 0;
    }

    function finishDrop() {
        const y = view.contentY;
        dragging = false;
        settling = false;
        elevation = 0;
        onto = -1;
        Qt.callLater(() => {
            view.contentY = Math.max(view.originY, Math.min(view.originY + Math.max(0, view.contentHeight - view.height), y));
        });
    }

    parent: view
    anchors.fill: parent
    z: 2
    onModelChanged: Qt.callLater(() => {
        if (settling && !drop.running)
            finishDrop();

    })

    MouseArea {
        id: pointer

        anchors.fill: parent
        enabled: !root.settling
        acceptedButtons: Qt.LeftButton
        pressAndHoldInterval: 300
        preventStealing: root.dragging
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
        onPressed: (mouse) => {
            root.from = root.view.indexAt(mouse.x, mouse.y + root.view.contentY);
            if (root.from < 0 || mouse.x >= width - root.rightGuard || (root.canLift && !root.canLift(root.from))) {
                mouse.accepted = false;
                return;
            }
            root.queue = root.model;
            root.pressedModel = root.model;
            const item = root.view.itemAtIndex(root.from);
            root.grabOffset = mouse.y + root.view.contentY - (item ? item.y : root.from * root.rowHeight);
        }
        onPressAndHold: {
            if (root.pressedModel !== root.model || (root.canHold && !root.canHold(root.from)) || (!root.allowSingle && root.queue.length < 2))
                return;

            root.view.cancelFlick();
            const task = root.queue[root.from];
            if (root.heldModel)
                root.grabOffset = Math.min(root.rowHeight - 1, root.grabOffset);

            root.holdTop = mouseY - root.grabOffset;
            if (root.heldModel) {
                root.queue = root.heldModel;
                root.from = root.queue.findIndex((r) => {
                    return r.id === task.id && r.kind === task.kind;
                });
            }
            root.to = root.from;
            root.dragging = true;
            root.elevation = 1;
            root.held();
            root.view.forceLayout();
            if (root.heldModel) {
                const row = root.view.itemAtIndex(root.from);
                root.view.contentY = (row ? row.y : root.from * root.rowHeight) - root.holdTop;
            }
            root.updateTarget();
        }
        onPositionChanged: root.updateTarget()
        onReleased: {
            if (!root.dragging)
                return;

            root.updateTarget();
            root.dropY = root.liftedY;
            root.settling = true;
            root.dragging = false;
            root.elevation = 0;
            if (root.pressedModel !== root.model) {
                root.to = root.from;
                root.onto = -1;
            } else if (root.onto >= 0) {
                root.nested(root.from, root.onto);
            } else {
                root.moved(root.from, root.to);
            }
            drop.restart();
        }
        onCanceled: root.finishDrop()
        onClicked: {
            if (!root.showing && root.pressedModel === root.model && root.from >= 0) {
                root.clicked(root.from);
            }
        }
    }

    NumberAnimation {
        id: drop

        target: root
        property: "dropY"
        to: root.to * root.rowHeight - root.view.contentY
        duration: Theme.revealMs
        easing.type: Easing.OutCubic
        onFinished: {
            if (root.pressedModel !== root.model || root.from === root.to) {
                root.finishDrop();
            }
        }
    }

    Timer {
        interval: 1000
        running: root.settling && !drop.running
        onTriggered: root.finishDrop()
    }

    Timer {
        interval: 100
        repeat: true
        running: root.scrollDirection !== 0
        onTriggered: {
            root.view.contentY = Math.max(root.view.originY, Math.min(root.view.originY + Math.max(0, root.view.contentHeight - root.view.height), root.view.contentY + root.scrollDirection * root.rowHeight));
            root.updateTarget();
        }
    }

    Rectangle {
        id: floating

        x: 4 * root.elevation
        y: (root.settling ? root.dropY : root.liftedY) - 2 * root.elevation
        width: parent.width - 8 * root.elevation
        height: root.rowHeight
        scale: 1 + 0.01 * root.elevation
        visible: root.showing
        radius: Theme.selectionRadius
        color: Theme.well

        RectangularShadow {
            anchors.fill: parent
            z: -1
            radius: floating.radius
            blur: 8
            offset.y: 3
            color: Theme.shadow
            opacity: root.elevation
        }

        Loader {
            anchors.fill: parent
            active: root.showing
            sourceComponent: root.lifted
        }

    }

    Behavior on elevation {
        NumberAnimation {
            duration: Theme.revealMs
            easing.type: Easing.OutCubic
        }

    }

}

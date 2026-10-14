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
    property var canLift: null
    property var canHold: null
    property var heldModel: null
    property bool allowSingle: false
    property var rows: []
    property bool dragging: false
    property bool settling: false
    readonly property bool showing: dragging || settling
    property real elevation: 0
    property real dropY: 0
    property int from: -1
    property int to: -1
    property real grabOffset: 0
    property real grabX: 0
    property real holdTop: 0
    property real holdHeight: 0
    property var pressedModel: null
    readonly property real liftedY: Math.max(0, Math.min(height - rowHeight, pointer.mouseY - grabOffset))
    readonly property real horizontalOffset: pointer.mouseX - root.grabX
    readonly property int scrollDirection: !dragging ? 0 : pointer.mouseY < rowHeight ? -1 : pointer.mouseY > height - rowHeight ? 1 : 0

    signal moved(int from, int to)
    signal clicked(int index)
    signal held()

    function updateTarget() {
        if (!dragging)
            return;

        const centre = view.contentY + liftedY + rowHeight / 2;
        const index = view.indexAt(1, centre);
        to = index < 0 ? (centre < view.originY ? 0 : rows.length - 1) : index;
    }

    function shift(index) {
        if (!showing)
            return 0;

        return index > from && index <= to ? -rowHeight : index < from && index >= to ? rowHeight : 0;
    }

    function finishDrop() {
        const y = view.contentY;
        dragging = false;
        settling = false;
        elevation = 0;
        Qt.callLater(() => {
            view.contentY = Math.max(view.originY, Math.min(view.originY + Math.max(0, view.contentHeight - view.height), y));
        });
    }

    parent: view
    anchors.fill: parent
    z: 2
    // A server reply may arrive before or after the drop animation finishes.
    onModelChanged: Qt.callLater(() => {
        if (settling && !drop.running)
            finishDrop();
    })

    // Keep the pointer grab on the view: delegates can be recycled or folded
    // while held, so grabbing a row would lose the drag as its model changes.
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
            root.rows = root.model;
            root.pressedModel = root.model;
            root.grabX = mouse.x;
            const item = root.view.itemAtIndex(root.from);
            root.grabOffset = mouse.y + root.view.contentY - (item ? item.y : root.from * root.rowHeight);
        }
        onPressAndHold: {
            if (root.pressedModel !== root.model || (root.canHold && !root.canHold(root.from)) || (!root.allowSingle && root.rows.length < 2))
                return;

            root.view.cancelFlick();
            root.holdHeight = root.view.height;
            const task = root.rows[root.from];
            if (root.heldModel)
                root.grabOffset = Math.min(root.rowHeight - 1, root.grabOffset);

            // Preserve the press location while a variable-height list folds.
            root.holdTop = mouseY - root.grabOffset;
            if (root.heldModel) {
                root.rows = root.heldModel;
                root.from = root.rows.findIndex((r) => {
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

    // Rejected or unchanged moves have no new model to end the settle.
    Timer {
        interval: 1000
        running: root.settling && !drop.running
        onTriggered: root.finishDrop()
    }

    // Scroll in row-sized steps so landing slots stay predictable at an edge.
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

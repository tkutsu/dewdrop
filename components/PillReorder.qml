import QtQuick
import qs

// Own module drag hit testing, cancellation and the drop indicator for an ordered pill.
Item {
    id: root
    required property Item pill
    anchors.fill: parent
    property bool dragging: false
    property Item dragSource: null
    property point dragPoint: Qt.point(0, 0)

    readonly property var _movable: root.pill.shown.filter(item => root.pill.order.includes(item.settingsKey))
    readonly property bool dragValid: root.pill.visible && dragSource !== null && dragSource.here && dragSource.visible
    // Later, not here: clearing dragSource now re-evaluates dragValid inside its own change.
    onDragValidChanged: if (dragging && !dragValid) Qt.callLater(root.cancelInvalidDrag)

    function cancelInvalidDrag(): void {
        if (dragging && !dragValid)
            cancelDrag();
    }

    function moduleAt(point): Item {
        if (!root.pill.contains(point))
            return null;
        for (const item of root._movable)
            if (item.contains(item.mapFromItem(root.pill, point)))
                return item;
        return null;
    }

    // Compare against the remaining modules so either side of the source is a no-op.
    function beforeAt(point): Item {
        for (const item of root._movable) {
            if (item === root.dragSource)
                continue;
            const middle = item.mapToItem(root.pill, item.width / 2, 0).x;
            if (point.x < middle)
                return item;
        }
        return null;
    }

    readonly property Item dropBefore: dragging ? beforeAt(dragPoint) : null
    // A drop just before the module that already follows the source leaves it where it is.
    readonly property bool dropMoves: dragging
        && dropBefore !== (_movable[_movable.indexOf(dragSource) + 1] ?? null)

    function cancelDrag(): void {
        dragging = false;
        dragSource = null;
    }

    // Resolve the drop from current geometry, including a drawer still settling.
    // A null point is a drag that ended without a release, which cancels.
    function finishDrag(point): void {
        if (dragging && dragValid && point !== null && root.pill.contains(point))
            RightPillOrder.move(dragSource.settingsKey, beforeAt(point)?.settingsKey ?? null,
                root._movable.map(item => item.settingsKey));
        cancelDrag();
    }

    // An ancestor handler observes child MouseAreas without swallowing their clicks.
    DragHandler {
        id: reorder
        parent: root.pill
        target: null
        enabled: root.pill.order.length > 0
        // Turning a handler off drops its grab without saying so.
        onEnabledChanged: if (!enabled) root.cancelDrag()
        acceptedButtons: Qt.LeftButton
        grabPermissions: root.moduleAt(centroid.pressPosition) !== null
            ? PointerHandler.CanTakeOverFromItems : PointerHandler.TakeOverForbidden
        onActiveChanged: {
            if (!active)
                return;
            root.dragSource = root.moduleAt(centroid.pressPosition);
            if (root.dragSource === null)
                return;
            root.dragPoint = centroid.position;
            root.dragging = true;
            OpenPopup.dismiss();
        }
        onCentroidChanged: if (active && root.dragging) root.dragPoint = centroid.position
        // Every end of the drag comes through here, released or not. Only a
        // release drops; centroid is reset by then, but the point keeps its place.
        onGrabChanged: (transition, point) => {
            const ends = [PointerDevice.UngrabExclusive, PointerDevice.CancelGrabExclusive, PointerDevice.OverrideGrabExclusive];
            if (!ends.includes(transition))
                return;
            const released = transition === PointerDevice.UngrabExclusive && point.state === EventPoint.Released;
            root.finishDrag(released ? root.pill.mapFromItem(null, point.scenePosition) : null);
        }
    }

    // Between the modules either side of the drop, splitting any margin they overlap by.
    DropLine {
        target: {
            if (!root.dropMoves || !root.pill.contains(root.dragPoint))
                return NaN;
            const items = root._movable.filter(item => item !== root.dragSource);
            const next = root.dropBefore;
            const previous = items[(next ? items.indexOf(next) : items.length) - 1];
            const left = previous?.mapToItem(root.pill, previous.width, 0).x;
            const right = next?.mapToItem(root.pill, 0, 0).x;
            return ((left ?? right) + (right ?? left)) / 2;
        }
    }

}

import QtQuick
import qs

// Own module drag hit testing, cancellation and the drop indicator for an ordered pill.
Item {
    id: root
    required property Item pill
    anchors.fill: parent
    property bool dragging: false
    property Item pressSource: null
    property Item dragSource: null
    property point dragPoint: Qt.point(0, 0)

    readonly property var _movable: root.pill.shown.filter(item => root.pill.order.includes(item.settingsKey) && !root.pill.lockedKeys.includes(item.settingsKey))
    readonly property Item dropPill: dragging ? targetAt(dragPoint) : root.pill
    // Keep a destination line in its pill while it fades after release.
    property Item indicatorPill: root.pill
    onDropPillChanged: if (dragging) indicatorPill = dropPill
    onDraggingChanged: if (dragging) indicatorPill = dropPill
    readonly property bool dragValid: root.pill.visible && dragSource !== null && dragSource.here && dragSource.visible
        && !root.pill.lockedKeys.includes(dragSource.settingsKey)
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

    // Only opted-in modules may cross to the paired pill on this bar.
    function targetAt(point): Item {
        const peer = root.pill.reorderPeer;
        return peer?.visible && peer.enabled && root.pill.transferableKeys.includes(root.dragSource?.settingsKey)
            && peer.contains(peer.mapFromItem(root.pill, point)) ? peer : root.pill;
    }

    // Compare against the remaining modules so either side of the source is a no-op.
    function beforeAt(point, target = root.pill): Item {
        for (const item of target.shown.filter(item => target.order.includes(item.settingsKey))) {
            if (item === root.dragSource)
                continue;
            const middle = item.mapToItem(target, item.width / 2, 0).x;
            if (point.x < middle)
                return item;
        }
        return null;
    }

    readonly property Item dropBefore: dragging ? beforeAt(dropPill.mapFromItem(root.pill, dragPoint), dropPill) : null
    // A drop just before the module that already follows the source leaves it where it is.
    readonly property bool dropMoves: dragging
        && (dropPill !== root.pill || dropBefore !== (_movable[_movable.indexOf(dragSource) + 1] ?? null))

    function cancelDrag(): void {
        dragging = false;
        pressSource = null;
        dragSource = null;
    }

    // Resolve the drop from current geometry, including a drawer still settling.
    // A null point is a drag that ended without a release, which cancels.
    function finishDrag(point): void {
        if (dragging && dragValid && point !== null) {
            const target = targetAt(point);
            const local = target.mapFromItem(root.pill, point);
            if (target.contains(local)) {
                const key = dragSource.settingsKey;
                const visible = target.shown.filter(item => target.order.includes(item.settingsKey)).map(item => item.settingsKey);
                if (target !== root.pill)
                    visible.push(key);
                target.orderController.move(key, beforeAt(local, target)?.settingsKey ?? null, visible);
                if (target !== root.pill)
                    target.moduleReceived(key);
            }
        }
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
        grabPermissions: root._movable.includes(root.pressSource)
            ? PointerHandler.CanTakeOverFromItems : PointerHandler.TakeOverForbidden
        onActiveChanged: {
            if (!active || !root._movable.includes(root.pressSource))
                return;
            root.dragSource = root.pressSource;
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
            // The pill can move before a drag starts; hit-test only at the press.
            if (transition === PointerDevice.GrabPassive) {
                root.pressSource = root.moduleAt(root.pill.mapFromItem(null, point.scenePosition));
                return;
            }
            if ([PointerDevice.UngrabPassive, PointerDevice.CancelGrabPassive, PointerDevice.OverrideGrabPassive].includes(transition)) {
                root.pressSource = null;
                return;
            }
            const ends = [PointerDevice.UngrabExclusive, PointerDevice.CancelGrabExclusive, PointerDevice.OverrideGrabExclusive];
            if (!ends.includes(transition))
                return;
            const released = transition === PointerDevice.UngrabExclusive && point.state === EventPoint.Released;
            root.finishDrag(released ? root.pill.mapFromItem(null, point.scenePosition) : null);
        }
    }

    // Between the modules either side of the drop, splitting any margin they overlap by.
    DropLine {
        parent: root.indicatorPill
        target: {
            const local = root.dropPill.mapFromItem(root.pill, root.dragPoint);
            if (!root.dropMoves || !root.dropPill.contains(local))
                return NaN;
            const items = root.dropPill.shown.filter(item => root.dropPill.order.includes(item.settingsKey) && item !== root.dragSource);
            const next = root.dropBefore;
            const previous = items[(next ? items.indexOf(next) : items.length) - 1];
            const left = previous?.mapToItem(root.dropPill, previous.width, 0).x;
            const right = next?.mapToItem(root.dropPill, 0, 0).x;
            return ((left ?? right) + (right ?? left)) / 2;
        }
    }

}

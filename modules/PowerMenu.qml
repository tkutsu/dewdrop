import QtQuick
import QtQuick.Effects
import qs
import qs.components
import qs.services

// A floating action pill with launcher-style folding and a CRT action exit.
OverlayWindow {
    id: root

    name: "powermenu"
    shown: Power.shown
    color: root.closing ? "black" : "transparent"
    inputItem: menuClip
    onDismissed: root.back()

    readonly property var menuActions: Power.actions
    readonly property int tileWidth: Math.max(96, Math.min(112, Math.floor((width - 64) / menuActions.length)))
    property var pending: null
    property int index: -1
    property point pointer: Qt.point(-1, -1)
    property bool pointerLive: false
    property bool closing: false
    property string command: ""
    property real reveal: root.opened ? 1 : 0
    property real vertical: 1
    property real horizontal: 1
    property real flash: 0
    property real afterglow: 0

    readonly property var entries: pending ? [
        {
            name: "Cancel",
            accept: false
        },
        {
            name: pending.name,
            accept: true
        }
    ] : root.menuActions

    onEntriesChanged: root.pointerLive = false

    Behavior on reveal {
        NumberAnimation {
            duration: Theme.revealMs
            easing.type: Easing.OutCubic
        }
    }

    // Every open, including a reopen during dismissal, starts unselected.
    function adopt(): void {
        crt.stop();
        root.closing = false;
        root.command = "";
        root.vertical = 1;
        root.horizontal = 1;
        root.flash = 0;
        root.afterglow = 0;
        root.pending = Power.armed;
        Power.armed = null;
        root.index = -1;
        root.pointerLive = false;
    }

    // Keep confirmations, and run the command only after the CRT finishes.
    function choose(i: int): void {
        if (root.closing || !root.shown)
            return;
        const entry = root.entries[i];
        if (!entry)
            return;
        if (root.pending) {
            if (entry.accept)
                root.execute(root.pending.arg);
            else
                root.back();
        } else if (entry.confirm) {
            root.pending = entry;
            root.index = -1;
        } else {
            root.execute(entry.arg);
        }
    }

    function execute(arg: string): void {
        if (arg === "--kill") {
            Power.run(arg);
            return;
        }
        root.command = arg;
        root.closing = true;
        crt.start();
    }

    // Escape restores the menu and cancels a command still waiting to run.
    function cancelCrt(): void {
        crt.stop();
        root.command = "";
        root.vertical = 1;
        root.horizontal = 1;
        root.flash = 0;
        root.afterglow = 0;
        root.closing = false;
        root.index = -1;
        root.pointerLive = false;
    }

    // Ignore incidental input once an action's final animation has begun.
    function back(): void {
        if (root.closing)
            return;
        if (root.pending) {
            root.pending = null;
            root.index = -1;
        } else {
            Power.shown = false;
        }
    }

    function move(step: int): void {
        root.index = root.index < 0 ? (step > 0 ? 0 : root.entries.length - 1) : (root.index + step + root.entries.length) % root.entries.length;
    }

    // Track the pointer in fixed screen coordinates, independent of tile layout.
    function track(p: point): void {
        const moved = root.pointerLive && (Math.abs(p.x - root.pointer.x) >= 1 || Math.abs(p.y - root.pointer.y) >= 1);
        root.pointer = p;
        root.pointerLive = true;
        if (!moved || root.closing)
            return;
        const buttons = root.pending ? answers : actions;
        for (let i = 0; i < root.entries.length; i++) {
            const tile = buttons.itemAt(i);
            if (!tile)
                continue;
            const local = tile.mapFromItem(inputSurface, p.x, p.y);
            if (local.x >= 0 && local.x < tile.width && local.y >= 0 && local.y < tile.height) {
                root.index = i;
                return;
            }
        }
        root.index = -1;
    }

    Component.onCompleted: root.adopt()

    Connections {
        target: Power

        function onShownChanged() {
            if (Power.shown) {
                root.adopt();
            } else if (root.closing) {
                // An external IPC close cancels the queued action.
                crt.stop();
                root.command = "";
            }
        }
    }

    // Outside the clip, so the shadow follows the folding edges.
    RectangularShadow {
        parent: inputSurface
        x: menuClip.x
        y: menuClip.y
        width: menuClip.width
        height: menuClip.height
        visible: menuClip.height > 0
        offset.y: Theme.shadowY
        radius: Math.min(22, menuClip.height / 2)
        blur: Theme.shadowBlur
        color: Theme.shadow
    }

    Item {
        id: inputSurface

        anchors.fill: parent
        focus: true
        enabled: root.shown
        layer.enabled: true
        transform: Scale {
            origin.x: inputSurface.width / 2
            origin.y: inputSurface.height / 2
            xScale: root.horizontal
            yScale: root.vertical
        }

        HoverHandler {
            onPointChanged: root.track(point.position)
            onHoveredChanged: if (!hovered) {
                root.index = -1;
                root.pointerLive = false;
            }
        }

        Keys.onPressed: function (event) {
            if (root.closing) {
                if (event.key === Qt.Key_Escape)
                    root.cancelCrt();
                event.accepted = true;
                return;
            }
            switch (event.key) {
            case Qt.Key_Escape:
                Power.shown = false;
                break;
            case Qt.Key_Left:
            case Qt.Key_Up:
            case Qt.Key_H:
            case Qt.Key_I:
            case Qt.Key_Backtab:
                root.move(-1);
                break;
            case Qt.Key_Right:
            case Qt.Key_Down:
            case Qt.Key_L:
            case Qt.Key_E:
                root.move(1);
                break;
            case Qt.Key_Tab:
                root.move(event.modifiers & Qt.ShiftModifier ? -1 : 1);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                root.choose(root.index);
                break;
            default:
                if (!root.pending && event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.menuActions.length) {
                    root.index = event.key - Qt.Key_1;
                    root.choose(root.index);
                    event.accepted = true;
                }
                return;
            }
            event.accepted = true;
        }

        // Keep content at its final size while the edges reveal or cover it.
        Item {
            id: menuClip

            readonly property int topEdge: Math.round(menuContent.implicitHeight * (1 - root.reveal) / 2)
            x: Math.round((root.width - width) / 2)
            y: Math.round((root.height - menuContent.implicitHeight) / 2) + topEdge
            width: menuContent.implicitWidth
            height: Math.max(0, menuContent.implicitHeight - topEdge * 2)
            clip: true

            Column {
                id: menuContent

                y: -menuClip.topEdge
                spacing: 32

                ActionPill {
                    id: actions

                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.pending === null
                    model: root.menuActions
                }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.pending !== null
                    spacing: 28

                    Glyph {
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 48
                        fontSize: 24
                        text: root.pending?.glyph ?? ""
                    }

                    Text {
                        width: Math.min(380, root.width - 64)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: root.pending?.question ?? ""
                        color: Theme.label
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.popupTextSize + 2
                        lineHeight: 1.2
                    }

                    ActionPill {
                        id: answers

                        anchors.horizontalCenter: parent.horizontalCenter
                        model: root.pending ? root.entries : []
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "white"
                opacity: root.flash
            }
        }
    }

    // One slab and a head/tail selector, using the workspace pill's material and motion.
    component ActionPill: Item {
        id: pill

        required property var model
        readonly property int pad: Theme.markInset
        readonly property Item selected: root.index >= 0 ? buttons.itemAt(root.index) : null
        readonly property bool held: {
            for (const child of cells.children)
                if (child.held === true)
                    return true;
            return false;
        }

        implicitWidth: cells.implicitWidth + pad * 2
        implicitHeight: 44

        function itemAt(i: int): Item {
            return buttons.itemAt(i);
        }

        Liquid {
            anchors.fill: parent
            box0: Qt.vector4d(0, 0, width, height)
            rimFrom: 0
            rimTo: height
            soften: Theme.glassSoften * 8
            tint: 0.58
            fill: Qt.vector4d(Theme.tint.r + 0.1, Theme.tint.g + 0.1, Theme.tint.b + 0.1, Theme.barBg.a)
        }

        MouseArea {
            anchors.fill: parent
        }

        Liquid {
            id: mark

            anchors.fill: parent
            visible: pill.selected !== null
            property bool placed: false
            onPlacedChanged: if (placed) {
                tailLeft = wantLeft;
                tailRight = wantRight;
                tailProgress = 1;
                roundness = 0;
            }

            onVisibleChanged: {
                if (visible)
                    Qt.callLater(() => mark.placed = mark.visible);
                else {
                    placed = false;
                    followTail();
                }
            }

            property real lift: pill.held ? 1 : 0
            Behavior on lift {
                SpringAnimation {
                    spring: Theme.springStiffness
                    damping: Theme.markDamping
                }
            }

            readonly property real edge: Theme.markInset - lift
            readonly property real slabTop: Theme.pillBorder + edge
            readonly property real thickness: pill.height - Theme.pillBorder - edge * 2
            readonly property color tone: Theme.mix(Theme.selectionStrong, Theme.markLifted, lift)
            readonly property real wantLeft: pill.selected ? cells.x + pill.selected.x + Theme.markInset : 0
            readonly property real wantRight: pill.selected ? cells.x + pill.selected.x + pill.selected.width - Theme.markInset : 0

            property real headLeft: wantLeft
            property real headRight: wantRight
            property real tailLeft: wantLeft
            property real tailRight: wantRight
            property point tailStart: Qt.point(wantLeft, wantRight)
            property real tailProgress: 1
            property real roundness: 0

            // A new destination keeps the tail wherever the previous move left it.
            function followTail(): void {
                if (!mark.placed) {
                    mark.tailLeft = mark.wantLeft;
                    mark.tailRight = mark.wantRight;
                    mark.tailProgress = 1;
                    mark.roundness = 0;
                    return;
                }
                mark.tailStart = Qt.point(mark.tailLeft, mark.tailRight);
                mark.tailProgress = 0;
            }

            onWantLeftChanged: followTail()
            onWantRightChanged: followTail()

            Behavior on headLeft {
                enabled: mark.placed
                SpringAnimation {
                    spring: Theme.springStiffness
                    damping: Theme.markDamping
                }
            }
            Behavior on headRight {
                enabled: mark.placed
                SpringAnimation {
                    spring: Theme.springStiffness
                    damping: Theme.markDamping
                }
            }
            FrameAnimation {
                running: mark.visible && mark.placed && (mark.tailProgress < 1 || mark.roundness > 0)

                // Distance and the tail's shrinking size accelerate the same cubic flow.
                onTriggered: {
                    const previousMid = mark.tailMid;
                    const distance = mark.apart / (mark.thickness * 4);
                    const shrink = 1 - mark.blobHeight / mark.thickness;
                    const speed = (1 + 0.75 * distance * distance) * (1 + 0.75 * shrink);
                    mark.tailProgress = Math.min(1, mark.tailProgress + frameTime * 1000 * speed / (Theme.markMs * 1.1));
                    const t = Math.max(0, (mark.tailProgress - 0.2) / 0.8);
                    const eased = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
                    const left = mark.tailStart.x + (mark.wantLeft - mark.tailStart.x) * eased;
                    const right = mark.tailStart.y + (mark.wantRight - mark.tailStart.y) * eased;
                    const velocity = mark.tailProgress < 1 && frameTime > 0 ? Math.abs((left + right) / 2 - previousMid) / frameTime : 0;
                    mark.tailLeft = left;
                    mark.tailRight = right;
                    // Ease into a ball as flow speeds up, and back into a pill at rest.
                    const pace = Math.min(1, velocity / (mark.thickness * 24));
                    const round = pace * pace * (3 - 2 * pace);
                    const roundingTime = round > mark.roundness ? 0.025 : 0.05;
                    mark.roundness += (round - mark.roundness) * (1 - Math.exp(-frameTime / roundingTime));
                    if (round === 0 && mark.roundness < 0.001)
                        mark.roundness = 0;
                }
            }

            readonly property bool atFirst: pill.selected?.index === 0
            readonly property bool atLast: pill.selected?.index === pill.model.length - 1
            readonly property real wallLeft: Theme.pillBorder
            readonly property real wallRight: pill.width - Theme.pillBorder
            readonly property real frontLeft: atFirst ? Math.max(headLeft - lift, wallLeft) : headLeft - lift
            readonly property real frontRight: atLast ? Math.min(headRight + lift, wallRight) : headRight + lift
            readonly property real pastLeft: atFirst ? wallLeft - (headLeft - lift) : 0
            readonly property real pastRight: atLast ? headRight + lift - wallRight : 0
            readonly property real press: {
                const t = Math.min(1, Math.max(pastLeft, pastRight, 0) / Theme.markPress);
                return 1 - (1 - t) * (1 - t);
            }
            readonly property real bulbEdge: Math.max(0, edge - Theme.markBulge * press)
            readonly property real bulbTop: Theme.pillBorder + bulbEdge
            readonly property real bulbThickness: pill.height - Theme.pillBorder - bulbEdge * 2
            readonly property real bulbWidth: press > 0 ? bulbThickness * 1.2 : 0
            readonly property real bulbLeft: pastRight > pastLeft ? wallRight - bulbWidth : wallLeft
            readonly property real headMid: (frontLeft + frontRight) / 2
            readonly property real tailMid: (tailLeft + tailRight) / 2
            readonly property real apart: Math.abs(headMid - tailMid)
            readonly property real neck: thickness * (1 - 0.6 * Math.pow(Math.min(1, apart / (thickness * 3)), 2))
            readonly property real tailWidth: tailRight - tailLeft + lift * 2
            readonly property real blobWidth: tailWidth + (neck - tailWidth) * roundness
            readonly property real blobHeight: thickness + (neck - thickness) * roundness

            box0: Qt.vector4d(tailMid - blobWidth / 2, slabTop + (thickness - blobHeight) / 2, blobWidth, blobHeight)
            box1: Qt.vector4d(frontLeft, slabTop, frontRight - frontLeft, thickness)
            box2: Qt.vector4d(Math.min(headMid, tailMid), slabTop + (thickness - neck) / 2, apart, neck)
            box3: Qt.vector4d(bulbLeft, bulbTop, bulbWidth, bulbThickness)
            reach: Theme.pillSpread * Math.min(1, apart / thickness)
            reaches: Qt.vector4d(reach, reach, reach, 3 * press)
            fill: Qt.vector4d(tone.r, tone.g, tone.b, tone.a)
            rimTop: Qt.vector4d(Theme.markRimTop.r, Theme.markRimTop.g, Theme.markRimTop.b, Theme.markRimTop.a)
            rimFrom: bulbTop
            rimTo: bulbTop + bulbThickness
        }

        Row {
            id: cells

            x: pill.pad
            height: pill.height

            Repeater {
                id: buttons

                model: pill.model

                delegate: Item {
                    id: button

                    required property int index
                    required property var modelData
                    readonly property bool held: picker.pressed

                    width: root.tileWidth
                    height: pill.height
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.name
                    Accessible.onPressAction: root.choose(index)

                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        Glyph {
                            visible: !!button.modelData.glyph
                            text: button.modelData.glyph ?? ""
                            height: pill.height
                            fontSize: 18
                            color: Theme.label
                        }

                        Text {
                            height: pill.height
                            verticalAlignment: Text.AlignVCenter
                            text: button.modelData.name
                            color: Theme.label
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.labelSize
                            font.weight: Theme.bodyWeight
                        }
                    }

                    MouseArea {
                        id: picker

                        anchors.fill: parent
                        enabled: root.shown && !root.closing
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.choose(button.index)
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.max(3, menuClip.width * root.horizontal)
        height: 3
        radius: height / 2
        color: "white"
        opacity: root.afterglow

        layer.enabled: root.afterglow > 0
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "white"
            shadowBlur: 0.6
            shadowOpacity: 0.8
        }
    }

    // Compress the menu vertically, then the phosphor line to a dot.
    SequentialAnimation {
        id: crt

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "vertical"
                to: 0.002
                duration: 260
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: root
                property: "flash"
                to: 0.8
                duration: 260
                easing.type: Easing.InQuad
            }
        }
        PropertyAction {
            target: root
            property: "afterglow"
            value: 1
        }
        PropertyAction {
            target: root
            property: "vertical"
            value: 0
        }
        PauseAnimation {
            duration: 55
        }
        NumberAnimation {
            target: root
            property: "horizontal"
            to: 0
            duration: 170
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: root
            property: "afterglow"
            to: 0
            duration: 110
        }
        PauseAnimation {
            duration: 40
        }
        ScriptAction {
            script: {
                const arg = root.command;
                root.command = "";
                if (arg !== "")
                    Power.run(arg);
                else
                    root.cancelCrt();
            }
        }
    }
}

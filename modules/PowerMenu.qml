import QtQuick
import QtQuick.Effects
import Quickshell.Wayland
import qs
import qs.components
import qs.services

// A floating action pill with launcher-style folding and a CRT action exit.
OverlayWindow {
    id: root

    name: "powermenu"
    shown: Power.shown
    color: "transparent"
    inputItem: menuClip
    WlrLayershell.keyboardFocus: root.shown || Power.blackout ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    onDismissed: root.back()

    readonly property var menuActions: Power.actions
    readonly property int tileWidth: Math.max(96, Math.min(112, Math.floor((width - 64) / menuActions.length)))
    property var pending: null
    property var confirmation: null
    property int index: -1
    property point pointer: Qt.point(-1, -1)
    property bool pointerLive: false
    property bool closing: false
    property string command: ""
    // The wallpaper as Backdrop draws it on this screen.
    readonly property var backdrop: Wallpaper.backdrops[root.screen?.name] ?? null
    readonly property var wallpaper: root.backdrop?.front ?? null
    readonly property bool wallpaperReady: !!root.backdrop?.ready && (!root.wallpaper.path || wallpaperImage.status === Image.Ready)
    readonly property real windowAlpha: 0.6
    // The pill and the backdrop open together, once both frames are in hand.
    property bool gaveUp: false
    readonly property bool backdropReady: desktop.hasContent && root.wallpaperReady || root.gaveUp
    property real reveal: root.opened && root.backdropReady ? 1 : 0
    property real shade: root.closing ? 1 : 0.2
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
    onPendingChanged: if (root.pending) root.confirmation = root.pending

    Behavior on reveal {
        NumberAnimation {
            duration: Theme.revealMs
            easing.type: Easing.OutCubic
        }
    }

    Behavior on shade {
        NumberAnimation {
            duration: Theme.fadeMs
            easing.type: Easing.InOutCubic
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

    // Capture before revealing the menu, avoiding feedback from our own overlay.
    ScreencopyView {
        id: desktop

        anchors.fill: parent
        captureSource: root.screen
        live: false
        paintCursor: false
        visible: false
    }

    // Still allow the menu if a frame never arrives.
    Timer {
        interval: 300
        running: true
        onTriggered: root.gaveUp = true
    }

    // The finished backdrop, fading in with the pill.
    Item {
        id: veil

        anchors.fill: parent
        opacity: root.reveal
        visible: opacity > 0

        // The wallpaper, cropped and panned the way Backdrop has it and
        // softened less than the windows, so they can fade back over it.
        Rectangle {
            anchors.fill: parent
            color: root.wallpaper?.path ? "black" : root.wallpaper?.color ?? "black"
            opacity: root.wallpaperReady ? 1 : 0
            visible: opacity > 0
            layer.enabled: visible
            layer.effect: MultiEffect {
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 32
                blur: 0.3 * root.reveal
            }

            // Only a wallpaper that lands after the menu opened fades in.
            Behavior on opacity {
                enabled: root.reveal > 0
                NumberAnimation { duration: Theme.fadeMs }
            }

            Image {
                id: wallpaperImage

                readonly property real zoom: root.wallpaper?.zoom ?? 1

                width: root.width * zoom
                height: root.height * zoom
                x: (root.width - width) / 2 + (root.wallpaper?.offsetX ?? 0)
                y: (root.height - height) / 2 + (root.wallpaper?.offsetY ?? 0)
                source: root.wallpaper?.path ? "file://" + root.wallpaper.path.split("/").map(encodeURIComponent).join("/") : ""
                sourceSize: Qt.size(Math.ceil(width * root.devicePixelRatio), Math.ceil(height * root.devicePixelRatio))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
            }
        }

        // The windows, blurred and faded back over the wallpaper. The blur
        // has to change after the capture lands, or MultiEffect never
        // applies it, so both blurs grow with the reveal.
        MultiEffect {
            anchors.fill: parent
            source: desktop
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 32
            blur: 0.6 * root.reveal
            opacity: root.wallpaperReady ? root.windowAlpha : 1
            visible: desktop.hasContent

            Behavior on opacity {
                enabled: root.reveal > 0
                NumberAnimation { duration: Theme.fadeMs }
            }
        }

        // Dim the desktop, then carry that shade into the CRT's black hold.
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: root.shade
        }
    }

    Item {
        id: inputSurface

        anchors.fill: parent
        focus: true
        enabled: root.shown || Power.blackout
        layer.enabled: root.closing
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
                if (event.key === Qt.Key_Escape) {
                    if (Power.blackout)
                        Power.blackout = false;
                    else
                        root.cancelCrt();
                }
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

            readonly property int pillHeight: 44
            readonly property int topEdge: Math.round(pillHeight * (1 - root.reveal) / 2)
            x: (root.width - width) / 2
            y: (root.height - pillHeight) / 2 + topEdge
            width: (root.pending ? answers.implicitWidth : actions.implicitWidth)
            height: Math.max(0, pillHeight - topEdge * 2)
            clip: true
            opacity: root.closing ? 0 : 1

            // Clear the pill quickly; the final CRT line is drawn separately.
            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutQuad
                }
            }

            Behavior on width {
                enabled: root.completed && root.shown && !root.closing
                NumberAnimation {
                    duration: Theme.fadeMs
                    easing.type: Easing.InOutCubic
                }
            }

            // Frosted glass: the backdrop behind the pill, blurred harder and
            // cut to the pill's shape, under its tint.
            ShaderEffectSource {
                id: behindPill

                width: menuClip.width
                height: menuClip.pillHeight
                sourceItem: veil
                sourceRect: Qt.rect(menuClip.x, menuClip.y - menuClip.topEdge, width, height)
                visible: false
            }

            Rectangle {
                id: pillShape

                width: menuClip.width
                height: menuClip.pillHeight
                radius: height / 2
                visible: false
                layer.enabled: true
            }

            MultiEffect {
                y: -menuClip.topEdge
                width: menuClip.width
                height: menuClip.pillHeight
                source: behindPill
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 64
                blur: root.reveal
                maskEnabled: true
                maskSource: pillShape
                maskSpreadAtMin: 1
            }

            Liquid {
                y: -menuClip.topEdge
                width: menuClip.width
                height: menuClip.pillHeight
                box0: Qt.vector4d(0, 0, width, height)
                rimFrom: 0
                rimTo: height
                fill: Qt.vector4d(Theme.tint.r + 0.1, Theme.tint.g + 0.1, Theme.tint.b + 0.1, Theme.barBg.a)
            }

            ActionPill {
                id: actions

                anchors.horizontalCenter: parent.horizontalCenter
                y: -menuClip.topEdge
                model: root.menuActions
                enabled: root.pending === null && !root.closing
                opacity: root.pending ? 0 : 1
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation { duration: Theme.fadeMs }
                }
            }

            ActionPill {
                id: answers

                anchors.horizontalCenter: parent.horizontalCenter
                y: -menuClip.topEdge
                // Retain the labels while confirmation fades back to the menu.
                model: root.confirmation ? [
                    { name: "Cancel", accept: false },
                    { name: root.confirmation.name, accept: true }
                ] : []
                enabled: root.pending !== null && !root.closing
                opacity: root.pending ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation { duration: Theme.fadeMs }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "white"
                opacity: root.flash
            }
        }
    }

    // Crossfade action rows inside the same resizing pill.
    component ActionPill: Item {
        id: pill

        required property var model
        readonly property int pad: Theme.markInset
        readonly property Item selected: pill.enabled && root.index >= 0 ? buttons.itemAt(root.index) : null
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

        MouseArea {
            anchors.fill: parent
        }

        FlowMark {
            anchors.fill: parent
            visible: pill.selected !== null
            resetWhenHidden: true
            held: pill.held
            slabHeight: pill.height
            wantLeft: pill.selected ? cells.x + pill.selected.x + Theme.markInset : 0
            wantRight: pill.selected ? cells.x + pill.selected.x + pill.selected.width - Theme.markInset : 0
            atFirst: pill.selected?.index === 0
            atLast: pill.selected?.index === pill.model.length - 1
            wallLeft: Theme.pillBorder
            wallRight: pill.width - Theme.pillBorder
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
                    Power.run(arg, true);
                else
                    root.cancelCrt();
            }
        }
    }
}

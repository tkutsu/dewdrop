import QtQuick
import qs

// Options in a capsule, as a Mac's segmented control in the dark: the chosen
// one sits on a lighter capsule raised off the well and lit from above,
// hairlines part the rest and step aside for it, and it springs across to a
// new pick. A press dims it; dragging along the capsule carries it through the
// options and the one it rests on when let go is chosen. Each option takes its
// label's room; in a wider row they share the rest evenly. For up to three
// short options (SettingRow.fitsCapsule); more, or longer, take a dropdown.
Rectangle {
    id: root

    property var setting: null
    readonly property var current: root.setting?.get()
    readonly property var options: root.setting?.options ?? []
    readonly property int chosenIndex: root.options.findIndex(option => option.value === root.current)
    // Where a drag along the capsule has the mark, until it is let go.
    property int scrubIndex: -1
    readonly property int shownIndex: root.scrubIndex >= 0 ? root.scrubIndex : root.chosenIndex
    // itemAt() is not a binding's dependency; the count is, so the shown one
    // is found again once the options are built.
    readonly property Item shown: root.shownIndex >= 0 && root.shownIndex < buttons.count ? buttons.itemAt(root.shownIndex) : null
    readonly property bool held: tap.pressed || scrub.active

    function choose(value) {
        if (value !== root.current)
            root.setting.set(value);
    }

    // The option under x, the nearest one past either end.
    function indexAt(x) {
        for (let i = 0; i < buttons.count; i++) {
            const option = buttons.itemAt(i);
            if (x < cells.x + option.x + option.width)
                return i;
        }
        return buttons.count - 1;
    }

    readonly property real naturalWidth: cells.children.reduce((total, child) => total + (child.natural ?? 0), Theme.markInset * 2)
    readonly property real spare: root.options.length ? Math.max(0, (root.width - root.naturalWidth) / root.options.length) : 0

    implicitWidth: root.naturalWidth
    implicitHeight: 22
    radius: height / 2
    color: Theme.well

    TapHandler {
        id: tap

        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: point => root.choose(root.options[root.indexAt(point.position.x)].value)
    }

    DragHandler {
        id: scrub

        target: null
        yAxis.enabled: false
        onCentroidChanged: if (active)
            root.scrubIndex = root.indexAt(centroid.position.x)
        onActiveChanged: if (!active && root.scrubIndex >= 0) {
            root.choose(root.options[root.scrubIndex].value);
            root.scrubIndex = -1;
        }
    }

    // A pixel of shadow under the mark, to raise it off the well.
    Rectangle {
        visible: mark.visible
        x: mark.x
        y: mark.y + 1
        width: mark.width
        height: mark.height
        radius: mark.radius
        color: Theme.shadow
    }

    Rectangle {
        id: mark

        // Place the initial selection directly, then spring to later changes.
        property bool placed: false
        onVisibleChanged: if (visible && !placed)
            Qt.callLater(() => { if (mark.visible) mark.placed = true; })

        visible: root.shown !== null
        x: root.shown ? cells.x + root.shown.x : Theme.markInset
        y: Theme.markInset
        width: root.shown?.width ?? 0
        height: root.height - Theme.markInset * 2
        radius: height / 2
        // Lit from above, the way the glass's rim is; flat while pressed.
        gradient: Gradient {
            GradientStop {
                position: 0
                color: root.held ? Theme.selection : Theme.selectionLifted
            }
            GradientStop {
                position: 1
                color: root.held ? Theme.selection : Theme.selectionStrong
            }
        }

        Behavior on x {
            enabled: mark.placed
            SpringAnimation {
                spring: Theme.switchSpring
                damping: Theme.switchDamping
            }
        }

        Behavior on width {
            enabled: mark.placed
            SpringAnimation {
                spring: Theme.switchSpring
                damping: Theme.switchDamping
            }
        }
    }

    Row {
        id: cells

        x: Theme.markInset
        height: root.height

        Repeater {
            id: buttons

            model: root.options

            Item {
                id: option

                required property var modelData
                required property int index
                readonly property bool isShown: option === root.shown
                readonly property real natural: label.implicitWidth + 20

                Accessible.role: Accessible.RadioButton
                Accessible.name: root.setting.title + ": " + option.modelData.label
                Accessible.checked: option.index === root.chosenIndex
                Accessible.onPressAction: if (option.enabled && option.visible)
                    root.choose(option.modelData.value)
                Accessible.onToggleAction: if (option.enabled && option.visible)
                    root.choose(option.modelData.value)
                // A popup's keys (Popup.qml) reach each option.
                readonly property var keyPress: () => root.choose(option.modelData.value)

                width: Math.round(option.natural + root.spare)
                height: root.height

                // The hairline before this option, out of the mark's way.
                Rectangle {
                    readonly property real at: cells.x + option.x
                    visible: option.index > 0 && (at < mark.x - 3 || at > mark.x + mark.width + 3)
                    width: 1
                    height: 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.stroke
                }

                PopupText {
                    id: label

                    anchors.centerIn: parent
                    text: option.modelData.label
                    font.pixelSize: Theme.captionSize
                    color: option.isShown ? Theme.fg : hover.hovered ? Theme.label : Theme.label2

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.fadeMs
                        }
                    }
                }

                HoverHandler {
                    id: hover
                }
            }
        }
    }
}

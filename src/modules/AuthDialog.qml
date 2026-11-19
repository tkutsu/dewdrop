import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.src.core
import qs.src.components
import qs.src.services

// The password panel polkit asks through (services/Polkit.qml), laid out the
// way a Mac asks for an administrator: a padlock, what wants doing as the
// title, whose password it takes, one field, and Cancel beside the default
// button. A wrong password shakes the panel and empties the field.
//
// Its own window on the Overlay layer, centred on the screen in use, and it
// holds the keyboard for as long as it is up, so a password typed for it can
// never land in a window behind. A click outside leaves it alone: an
// administrator's request is answered, not dismissed by a stray press.
// Escape cancels.
//
// Hyprland fades the whole surface, blur and all, as it maps and unmaps
// (dewdrop.lua's quickshell:polkit rule), so the window can come and go with
// the request: shell.qml loads it only while one is up.
PanelWindow {
    id: root

    // The request: Polkit.flow, or a stand-in in the tests.
    required property var flow

    readonly property var identities: root.flow?.identities ?? []
    readonly property int chosen: root.identities.indexOf(root.flow?.selectedIdentity)
    readonly property bool mine: root.flow?.selectedIdentity?.string === Quickshell.env("USER")
    readonly property bool asking: root.flow?.isResponseRequired ?? false
    // Sent, and the answer not back yet.
    property bool submitted: false
    readonly property bool checking: root.submitted && !root.asking
    // The last try was refused; cleared by typing again.
    property bool refused: false
    // Whether Caps Lock is on, for the arrow in the field.
    property bool capsLock: Keyboard.capsLock

    readonly property int boxWidth: Theme.popupWidth
    readonly property int pad: 20

    function submit(): void {
        if (!root.asking)
            return;
        root.submitted = true;
        root.flow.submit(field.text);
    }

    function cancel(): void {
        root.flow?.cancelAuthenticationRequest();
    }

    // polkit's own words, as a sentence: pkexec quotes `like this', and a
    // quoted path is kept on one line rather than broken after a slash.
    function sentence(text: string): string {
        const s = text.trim().replace(/`([^']*)'/g, (_, quoted) => "“" + quoted.replace(/\//g, "/⁠") + "”");
        return s && !/[.!?…]$/.test(s) ? s + "." : s;
    }

    function nameOf(identity: var): string {
        return identity?.displayName || identity?.string || "";
    }

    Component.onCompleted: {
        root.screen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null;
        Keyboard.refresh();
    }

    // Hyprland's answer, once it is in; the keys keep it from there.
    Connections {
        target: Keyboard

        function onCapsLockChanged(): void {
            root.capsLock = Keyboard.capsLock;
        }
    }

    // A second request queued behind this one arrives in the same window.
    onFlowChanged: {
        field.text = "";
        root.submitted = false;
        root.refused = false;
    }

    Connections {
        target: root.flow

        function onAuthenticationFailed(): void {
            field.text = "";
            root.submitted = false;
            root.refused = true;
            if (!Theme.reduceMotion)
                shake.restart();
        }

        function onIsResponseRequiredChanged(): void {
            if (root.asking)
                field.forceActiveFocus();
        }
    }

    WlrLayershell.namespace: "quickshell:polkit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Only the panel, and the user menu while it is open, take the pointer;
    // the rest of the screen stays clickable.
    mask: Region {
        item: box
        Region { item: picker.popup.visible ? picker.popup.contentItem.parent : null }
    }

    BackdropProbe {
        id: under

        screen: root.screen
        area: Qt.rect(box.x, box.y, box.width, box.height)
        active: true
    }

    RectangularShadow {
        x: box.x
        y: box.y
        width: box.width
        height: box.height
        offset.y: Theme.shadowY
        radius: box.radius
        blur: Theme.shadowBlur
        color: Theme.shadow
    }

    Rectangle {
        id: box

        // Where the shake has it, left or right of centre.
        property real shift: 0

        x: Math.round((root.width - width) / 2 + box.shift)
        // A touch above centre, where the eye already is.
        y: Math.round((root.height - height) * 0.45)
        width: root.boxWidth
        height: column.implicitHeight + root.pad * 2
        radius: Theme.panelRadius
        color: Theme.frostOver(under.luma)

        Accessible.role: Accessible.Dialog
        Accessible.name: title.text

        Rim {
            anchors.fill: parent
            radius: box.radius
            z: 10
        }

        // A Mac's shake: three swings, each smaller, a third of a second.
        SequentialAnimation {
            id: shake

            NumberAnimation { target: box; property: "shift"; to: -10; duration: 40; easing.type: Easing.OutSine }
            NumberAnimation { target: box; property: "shift"; to: 9; duration: 70; easing.type: Easing.InOutSine }
            NumberAnimation { target: box; property: "shift"; to: -6; duration: 65; easing.type: Easing.InOutSine }
            NumberAnimation { target: box; property: "shift"; to: 4; duration: 60; easing.type: Easing.InOutSine }
            NumberAnimation { target: box; property: "shift"; to: 0; duration: 50; easing.type: Easing.InSine }
        }

        Column {
            id: column

            x: root.pad
            y: root.pad
            width: box.width - root.pad * 2

            Glyph {
                x: Math.round((column.width - width) / 2)
                text: Theme.glyph.lock
                fontSize: 44
                color: Theme.fg
            }

            Item { width: 1; height: 10 }

            PopupText {
                id: title
                width: column.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font.weight: Font.Bold
                text: root.sentence(root.flow?.message ?? "")
            }

            Item { width: 1; height: 4 }

            PopupText {
                width: column.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Theme.label2
                font.pixelSize: Theme.captionSize
                text: root.identities.length > 1 ? "Enter an administrator’s password." : root.mine ? "Enter your password to allow this." : `Enter the password for ${root.nameOf(root.flow?.selectedIdentity)} to allow this.`
            }

            Item { width: 1; height: 16 }

            // Whose password, when polkit would take more than one.
            SettingDropdown {
                id: picker

                visible: root.identities.length > 1
                width: column.width
                setting: ({
                    title: "User",
                    options: root.identities.map((identity, at) => ({ label: root.nameOf(identity), value: at })),
                    get: () => root.chosen,
                    set: at => {
                        root.flow.selectedIdentity = root.identities[at];
                        field.forceActiveFocus();
                    }
                })
            }

            Item { width: 1; height: picker.visible ? 8 : 0 }

            // A Mac's password field: a soft rounded well, round dots with
            // air between them, a focus ring that settles onto it as it
            // takes the keys, and the Caps Lock arrow while Caps Lock is on.
            // A wrong password shakes the panel; the field itself stays calm.
            Item {
                width: column.width
                height: 28

                // Drawn round the well, touching it. It comes in from a
                // wider, fainter ring and closes onto the field, as macOS's
                // does.
                Rectangle {
                    property real gap: field.activeFocus || Theme.reduceMotion ? 3 : 9

                    anchors.fill: well
                    anchors.margins: -gap
                    radius: well.radius + gap
                    color: "transparent"
                    border.width: 3
                    border.color: Qt.rgba(1, 1, 1, 0.24)
                    opacity: field.activeFocus ? 1 : 0

                    Behavior on gap {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                }

                Rectangle {
                    id: well

                    anchors.fill: parent
                    radius: 7
                    color: Qt.rgba(1, 1, 1, field.activeFocus ? 0.1 : 0.07)
                    border.width: Theme.pillBorder
                    border.color: Theme.stroke

                    TextInput {
                        id: field

                        Accessible.role: Accessible.EditableText
                        Accessible.name: placeholder.text
                        Accessible.passwordEdit: echoMode === TextInput.Password

                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: trail.width > 0 ? trail.width + 16 : 10
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        focus: true
                        readOnly: !root.asking
                        echoMode: root.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                        // Never seen: it only spaces the characters drawn over it.
                        passwordCharacter: "●"
                        readonly property bool masked: echoMode === TextInput.Password
                        color: masked ? "transparent" : Theme.fg
                        selectionColor: Theme.textSelection
                        selectedTextColor: masked ? "transparent" : Theme.fg
                        cursorDelegate: TextCaret { textInput: field }
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.popupTextSize
                        font.letterSpacing: echoMode === TextInput.Password ? 2 : 0

                        Component.onCompleted: forceActiveFocus()
                        onTextEdited: root.refused = false

                        // Caps Lock, followed from the keys once the panel has
                        // asked Hyprland: the key itself flips it, and a letter
                        // says it by coming out upper case without Shift or
                        // lower with it.
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_CapsLock)
                                root.capsLock = !root.capsLock;
                            else if (event.text && event.text.toLowerCase() !== event.text.toUpperCase())
                                root.capsLock = (event.text === event.text.toUpperCase()) !== !!(event.modifiers & Qt.ShiftModifier);
                            event.accepted = false;
                        }
                        Keys.onReturnPressed: root.submit()
                        Keys.onEnterPressed: root.submit()
                        Keys.onEscapePressed: root.cancel()

                        TextMenu {}

                        // The password as Password Fields' Character draws it, over
                        // the field's own characters, which stay unseen so the
                        // caret, selection and clicks still land on them. Each
                        // takes one character's room, from where the first
                        // one stands as the field scrolls.
                        PasswordGlyphs {
                            readonly property real step: field.text.length && field.passwordCharacter
                                ? field.positionToRectangle(1).x - field.positionToRectangle(0).x : 0

                            visible: field.masked
                            x: field.cursorRectangle.x - field.cursorPosition * step
                            anchors.verticalCenter: parent.verticalCenter
                            count: field.text.length
                            cell: step
                        }

                        // polkit's prompt, "Password: ", as a field's placeholder.
                        PopupText {
                            id: placeholder
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !field.text
                            text: (root.flow?.inputPrompt ?? "").replace(/[:\s]+$/, "") || "Password"
                            color: Theme.label3
                        }
                    }

                    Row {
                        id: trail

                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.capsLock && !root.checking
                            text: Theme.glyph.capsLock
                            fontSize: Theme.popupGlyphSize
                            color: Theme.label2
                        }

                        Spinner {
                            id: spinner
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.checking
                        }
                    }
                }
            }

            // What PAM had to add: a fingerprint reader's prompt, an expired
            // password. Wrong passwords say so by the shake alone.
            PopupText {
                readonly property string said: root.flow?.supplementaryMessage ?? ""

                visible: said !== ""
                topPadding: 6
                width: column.width
                wrapMode: Text.Wrap
                font.pixelSize: Theme.footnoteSize
                color: root.flow?.supplementaryIsError ? Theme.warn : Theme.label2
                text: root.sentence(said)
            }

            Item { width: 1; height: 16 }

            // The default button last, as on a Mac, and filled; both the
            // same width so the pair reads as one choice.
            Row {
                spacing: 8

                PopupButton {
                    width: (column.width - 8) / 2
                    height: 24
                    framed: true
                    label: "Cancel"
                    textSize: Theme.popupTextSize
                    onTapped: root.cancel()
                }

                PopupButton {
                    width: (column.width - 8) / 2
                    height: 24
                    framed: true
                    lit: true
                    live: root.asking
                    label: "Allow"
                    textSize: Theme.popupTextSize
                    onTapped: root.submit()
                }
            }
        }
    }
}

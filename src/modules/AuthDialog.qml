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
    // Whether Caps Lock is on, or Shift held, for the arrow in the field.
    property bool capsLock: Keyboard.capsLock
    property bool shift: false

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

    // An empty field for a fresh question: an answer sent stays in it, as
    // dots, only until polkit replies, so it is never shown in the clear to
    // the next prompt or offered to another user.
    function reset(): void {
        field.text = "";
        root.submitted = false;
        root.refused = false;
    }

    // A second request queued behind this one arrives in the same window.
    onFlowChanged: root.reset()

    Connections {
        target: root.flow

        function onAuthenticationFailed(): void {
            root.reset();
            root.refused = true;
            flushing.restart();
            if (!Theme.reduceMotion)
                shake.restart();
        }

        // Another prompt in the same conversation (a one-time code after
        // the password): the last answer was taken.
        function onIsResponseRequiredChanged(): void {
            if (!root.asking)
                return;
            if (root.submitted)
                root.reset();
            field.forceActiveFocus();
        }

        // Another user starts a new conversation.
        function onSelectedIdentityChanged(): void {
            root.reset();
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

            // The password field, drawn as the lock screen draws its own: a
            // capsule, the dots rising into it, "Enter Password" just after
            // the caret, and Caps Lock and the keyboard layout at its end.
            // A wrong password shakes the panel and flashes the capsule's
            // edge, as it does the lock's.
            Item {
                id: capsule

                // 0 to 1 and back on a refusal: the edge's warning.
                property real alarm: 0

                width: column.width
                height: 32

                // Under Reduce Motion this is all a refusal shows.
                SequentialAnimation {
                    id: flushing

                    NumberAnimation { target: capsule; property: "alarm"; to: 1; duration: 80 }
                    PauseAnimation { duration: 400 }
                    NumberAnimation { target: capsule; property: "alarm"; to: 0; duration: 400 }
                }

                Rectangle {
                    id: well

                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.12 + 0.06 * capsule.alarm)
                    border.width: 1
                    border.color: Qt.tint(Theme.stroke, Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, capsule.alarm))

                    TextInput {
                        id: field

                        Accessible.role: Accessible.EditableText
                        Accessible.name: placeholder.text
                        Accessible.passwordEdit: echoMode === TextInput.Password

                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: trail.width > 0 ? trail.width + 20 : 14
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        focus: true
                        readOnly: !root.asking
                        // An answer sent stays dots whatever the next prompt asks.
                        echoMode: root.flow?.responseVisible && !root.submitted ? TextInput.Normal : TextInput.Password
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
                        // lower with it. Shift held shows the arrow too, as on
                        // the lock.
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_CapsLock)
                                root.capsLock = !root.capsLock;
                            else if (event.key === Qt.Key_Shift)
                                root.shift = true;
                            else if (event.text && event.text.toLowerCase() !== event.text.toUpperCase())
                                root.capsLock = (event.text === event.text.toUpperCase()) !== !!(event.modifiers & Qt.ShiftModifier);
                            event.accepted = false;
                        }
                        Keys.onReleased: event => {
                            if (event.key === Qt.Key_Shift)
                                root.shift = false;
                            event.accepted = false;
                        }
                        Keys.onReturnPressed: root.submit()
                        Keys.onEnterPressed: root.submit()
                        Keys.onEscapePressed: root.cancel()
                        onActiveFocusChanged: if (!activeFocus)
                            root.shift = false

                        TextMenu { frame: well }

                        // The password's dots, drawn over the field's own
                        // characters so each can fade in as it rises. Those stay
                        // unseen, so the caret, selection and clicks still land
                        // on them. Each dot takes one character's room, from
                        // where the first one stands as the field scrolls.
                        //
                        // That room is the font's measure of the character,
                        // known before the field has laid out the key just
                        // typed. Read off the field's own layout, the first key
                        // measured nothing: its dot sat on the caret and jumped
                        // back a cell when the second came.
                        TextMetrics {
                            id: room
                            font: field.font
                            text: field.passwordCharacter
                        }

                        PasswordDots {
                            visible: field.masked
                            x: field.cursorRectangle.x - field.cursorPosition * room.advanceWidth
                            anchors.verticalCenter: parent.verticalCenter
                            count: field.text.length
                            cell: room.advanceWidth
                        }

                        // polkit's prompt as the placeholder, just after the
                        // caret: its "Password: " in the lock's words.
                        PopupText {
                            id: placeholder

                            readonly property string prompt: (root.flow?.inputPrompt ?? "").replace(/[:\s]+$/, "")

                            x: 4
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !field.text
                            text: !prompt || prompt === "Password" ? "Enter Password" : prompt
                            color: Theme.label2
                        }
                    }

                    // Caps Lock, the layout when there is more than one (a
                    // click moves to the next), and the spinner while the
                    // password is checked.
                    Row {
                        id: trail

                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        // The arrow over what sits beside the text, as on a Mac.
                        HoverHandler { cursorShape: Qt.ArrowCursor }

                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: (root.capsLock || root.shift) && !root.checking
                            text: Theme.glyph.capsLock
                            fontSize: Theme.popupGlyphSize
                            color: Theme.label2
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Keyboard.layouts.length > 1 && !root.checking
                            text: Keyboard.short
                            color: switcher.hovered ? Theme.fg : Theme.label2
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.captionSize
                            font.weight: Font.DemiBold

                            HoverHandler {
                                id: switcher
                            }
                            TapHandler {
                                onTapped: Keyboard.next()
                            }
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

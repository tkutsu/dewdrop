import QtQuick

// A MouseArea told what each button does, rather than handed one onClicked to
// sort the buttons out in:
//
//     actions: ({
//         [Qt.LeftButton]: () => Launcher.toggle(),
//         [Qt.RightButton]: () => Power.toggle()
//     })
//
// The table is the whole of what clicking means. A click runs its button's
// entry, and `acting` — what a press-in reads — is true only while a button
// that has one is held. A button left out, or mapped to null because it has
// nothing to do right now, neither runs nor dips: a dip under a button with
// nothing behind it promises a click that is not coming.
MouseArea {
    id: root

    property var actions: ({})
    property string name: ""
    property var pressAction: root.actions[Qt.LeftButton]
    // What the pointer does here without clicking: a tooltip to rest on, a
    // wheel to turn. The one that scrolls also says so with scroll actions
    // of its own.
    property bool hovers: false
    property bool scrolls: false
    // Buttons answered by a layer laid over this area (BarItem's pin and
    // popup opener), told here so the area can name them as its own.
    property list<int> moreButtons: []
    // What the description says before the pointer line (BarItem's tooltip).
    property string hint: ""
    readonly property bool presses: !!(root.acceptedButtons & Qt.LeftButton) && !!root.pressAction

    // Qt's accessibility has nothing for a right or middle click or a hover,
    // so whatever the pointer can do here beyond the press is named on the
    // description's last line, "Pointer: right click, scroll", for a screen
    // reader to read and a pointer tool (wayhint's verbs) to parse. Any one
    // of them keeps the area in the tree with its extents.
    function answers(button: int): bool {
        return root.moreButtons.includes(button) || (!!(root.acceptedButtons & button) && !!root.actions[button]);
    }
    readonly property list<string> verbs: [root.answers(Qt.RightButton) ? "right click" : "", root.answers(Qt.MiddleButton) ? "middle click" : "", root.hovers ? "hover" : "", root.scrolls ? "scroll" : ""].filter(verb => verb !== "")

    Accessible.role: root.presses ? Accessible.Button : Accessible.StaticText
    Accessible.name: root.name
    Accessible.description: [root.hint, root.verbs.length > 0 ? "Pointer: " + root.verbs.join(", ") : ""].filter(line => line !== "").join("\n")
    Accessible.ignored: root.name === "" || !(root.presses || root.verbs.length > 0)
    Accessible.onPressAction: if (root.enabled && root.visible)
        root.pressAction?.()

    readonly property bool acting: pressed && !!root.actions[pressedButtons]

    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function (mouse) {
        const action = root.actions[mouse.button];
        if (action)
            action();
    }
}

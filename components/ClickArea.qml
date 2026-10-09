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

    Accessible.role: Accessible.Button
    Accessible.name: root.name
    Accessible.ignored: root.name === "" || !(root.acceptedButtons & Qt.LeftButton) || !root.pressAction
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

import QtQuick
import qs.src.core

// A row of a menu, as every menu here draws them (the tray's MenuPopup, the
// fields' EditMenu): 22 high, the grey fill while lit, the label in the
// menu's text colours and faded while it cannot be chosen, or a hairline when
// it is a separator. A menu puts its own marks in front of the label (`lead`)
// or after it (`trailing`) and says when the row is `hot`.
//
// `choose()` acknowledges a choice: the fill goes out and
// comes back once, and only then does `picked` fire for the menu to act and
// close. Without it a menu that vanished on the click left you to work out
// from the result which row you hit.
Item {
    id: row

    property string text
    property bool separator: false
    // The pointer or the keys are on it.
    property bool hot: false
    // Another row of the same menu has been chosen: the menu is saying which
    // row it took, so no other lights up while it fades.
    property bool frozen: false
    // Where the label starts, and the room kept after it.
    property int lead: row.pad
    property int trailing: 0

    // The air on each side of a row's text, and half of it above and below:
    // a menu row is a target to point at rather than something to read
    // around, and the tighter pair keeps a long app menu to a column.
    readonly property int pad: Theme.popupInset
    readonly property alias label: label

    property bool chosen: false
    property bool blinkOn: true
    readonly property bool lit: row.chosen ? row.blinkOn : !row.frozen && row.hot

    signal picked

    // Whether the choice was taken: not for a separator, a row that cannot
    // be chosen, or once the menu has a choice already.
    function choose(): bool {
        if (row.separator || !row.enabled || row.frozen || row.chosen)
            return false;
        row.chosen = true;
        blink.start();
        return true;
    }

    implicitWidth: row.separator ? 0 : Math.max(120, row.lead + label.implicitWidth + row.pad + row.trailing)
    height: row.separator ? Theme.selectionInset * 2 : 22

    Accessible.role: Accessible.MenuItem
    Accessible.name: row.text
    Accessible.ignored: row.separator

    Rectangle {
        anchors.fill: parent
        visible: !row.separator
        radius: Theme.selectionRadius
        color: row.lit ? Theme.selection : "transparent"
    }

    // As wide as the highlight, as the popups' sections are divided.
    PopupSeparator {
        anchors.centerIn: parent
        visible: row.separator
        width: parent.width
    }

    PopupText {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        x: row.lead
        visible: !row.separator
        text: row.text
        color: row.lit ? Theme.menuSelectionText : Theme.menuText
        opacity: row.enabled ? 1 : 0.4
    }

    SequentialAnimation {
        id: blink

        PropertyAction { target: row; property: "blinkOn"; value: false }
        PauseAnimation { duration: Theme.blinkMs }
        PropertyAction { target: row; property: "blinkOn"; value: true }
        PauseAnimation { duration: Theme.blinkMs }
        ScriptAction { script: row.picked() }
    }
}

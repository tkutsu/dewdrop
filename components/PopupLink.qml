import QtQuick
import qs

// The way out to the app that does all of what a popup does some of, at the
// popup's foot under a PopupSeparator: "Network Settings…", as the Mac's menu
// extras end. Whoever uses it puts the popup away and opens the app.
PopupRow {
    id: root

    property string text: ""

    name: root.text
    height: 22
    gesturePolicy: TapHandler.ReleaseWithinBounds

    PopupText {
        x: Theme.popupInset
        anchors.verticalCenter: parent.verticalCenter
        width: root.width - Theme.popupInset * 2
        elide: Text.ElideRight
        text: root.text
    }
}

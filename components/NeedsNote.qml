import QtQuick
import qs

// What a feature is missing, in place of what it would have shown: "Network
// Settings needs network-manager-applet. Install". Install runs the install
// command in the terminal, and the feature comes back once the terminal
// closes. Hidden while nothing is missing.
PopupNote {
    id: root

    // "Network Settings"; empty for a plain "Needs …".
    property string feature: ""
    property var programs: []
    // A popup closes on Install; a settings page stays.
    property bool dismisses: true

    visible: text !== ""
    textFormat: Text.RichText
    text: Tools.needs(root.feature, root.programs, Theme.label2)
    onLinkActivated: link => {
        if (root.dismisses)
            OpenPopup.dismiss();
        Tools.follow(link, root.programs);
    }

    HoverHandler {
        cursorShape: root.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
}

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// custom/email
BarItem {
    // #custom-email.loading { opacity: 0.55 }
    opacity: Email.loaded ? 1 : Theme.dimOpacity

    tooltip: Email.tooltip
    quiet: Email.count === 0

    BadgedGlyph {
        Layout.fillHeight: true
        glyph: Email.icon
        glyphSize: Theme.glyphSizeLarge
        badge: Email.label
    }

    onClicked: function (mouse) {
        if (mouse.button === Qt.LeftButton)
            Quickshell.execDetached([Quickshell.env("HOME") + "/_scripts/pwa-gmail.sh"]);
        else if (mouse.button === Qt.RightButton)
            Email.refresh();
    }
}

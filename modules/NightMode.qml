import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// custom/nightmode: left click opens the brightness popup, right click
// toggles the mode, scroll steps the backlight.
BarItem {
    id: root
    name: "Display"
    tooltip: NightMode.tooltip
    tooltipEnabled: !root.feedbackVisible
    popup: DisplayPopup {}
    // Keep reduced brightness visible; full brightness can stay in the drawer.
    quiet: NightMode.brightness === 100
    Layout.leftMargin: -1
    Layout.rightMargin: -1

    // Reserve one icon slot so the narrower dim bulb cannot resize the bar.
    Item {
        Layout.fillHeight: true
        implicitWidth: Math.max(onRuler.implicitWidth, offRuler.implicitWidth)

        Glyph {
            x: Math.round((parent.width - width) / 2)
            height: parent.height
            text: NightMode.icon
            fontSize: Theme.glyphSize - 1
            nudge: -1
        }
        Glyph {
            id: onRuler
            text: Theme.glyph.nightOn
            fontSize: Theme.glyphSize - 1
            opacity: 0
        }
        Glyph {
            id: offRuler
            text: Theme.glyph.nightOff
            fontSize: Theme.glyphSize - 1
            opacity: 0
        }
    }

    actions: ({
            [Qt.RightButton]: () => NightMode.toggle()
        })

    scrolls: true
    Accessible.onScrollUpAction: scrollUp()
    Accessible.onScrollDownAction: scrollDown()
    onScrollUp: root.adjustBrightness(true)
    onScrollDown: root.adjustBrightness(false)

    property bool feedbackVisible: false

    // Extend the readout without closing and reopening its surface.
    function adjustBrightness(up: bool): void {
        NightMode.nudge(up);
        if (OpenPopup.owner === null && !root.pillDragging) {
            root.feedbackVisible = true;
            feedback.restart();
        }
    }

    Timer {
        id: feedback
        interval: 1200
        onTriggered: root.feedbackVisible = false
    }

    Connections {
        target: OpenPopup
        function onOwnerChanged(): void {
            if (OpenPopup.owner !== null) {
                root.feedbackVisible = false;
                feedback.stop();
            }
        }
    }

    HoverPopup {
        parent: root
        anchorItem: root
        open: root.feedbackVisible && root.visible && !root.pillDragging && !Tooltips.blocked
        popup: BrightnessLevelPopup {}
    }
}

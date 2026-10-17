import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// custom/language: left click lists the layouts, right click and the wheel
// step through them.
BarItem {
    id: root
    name: "Keyboard layout"
    textPress: true
    tooltip: Keyboard.layout
    popup: LanguagePopup {}
    forceShown: showTimer.running || bounceDelay.running || bounce.running
    contentAnimating: bounce.running

    Connections {
        target: Keyboard

        function onSwitched() {
            const hidden = root.stowed;
            if (Settings.layoutChangeBounce) {
                showTimer.restart();
                // Let a hidden module unfold before its label leaves the line.
                if (hidden || bounceDelay.running)
                    bounceDelay.restart();
                else
                    bounce.restart();
            }
        }
    }

    Timer {
        id: showTimer
        interval: 3000
    }

    Timer {
        id: bounceDelay
        interval: Theme.foldLandMs
        onTriggered: bounce.restart()
    }

    Bounce {
        id: bounce
        loops: 1
        periodMs: Math.ceil(flightMs)
    }

    BarText {
        Layout.fillHeight: true
        text: Keyboard.short
        fontSize: Theme.languageTextSize
        transform: Translate { y: bounce.offset }
        opacity: bounce.fade
        // Two capitals in a row of glyphs: centred on their ink like the
        // glyphs, not on a cap height the glyphs do not have.
        opticalCentre: true
    }

    actions: ({
            [Qt.RightButton]: () => Keyboard.next()
        })

    scrolls: true
    Accessible.onScrollUpAction: scrollUp()
    Accessible.onScrollDownAction: scrollDown()
    onScrollUp: Keyboard.next()
    onScrollDown: Keyboard.prev()
}

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.src.core
import qs.src.components
import qs.src.services

// custom/audio. Scroll is Audio.step, which the popup shares.
//
// One glyph, and the level only as how far the waves coming off it have lit —
// the way the menu bar's sound item does it. A dial or a number for volume was
// tried twice (a ring round the icon, then a pill whose outline was the
// gauge) and both were a whole island for a figure the ears already know.
BarItem {
    id: root
    name: "Audio"

    // The level the waves only hint at; which device is the popup's to say.
    tooltip: !Audio.connected ? "No output" : Audio.muted ? "Muted" : `Volume ${Audio.volume}%`
    tooltipEnabled: !root.feedbackVisible
    popup: AudioPopup {}
    // Nothing to play through — no speaker, no headphones in the jack — is
    // nothing to set a volume on either, so it waits in the drawer until an
    // output turns up.
    quiet: !Audio.connected

    // A pixel nearer the language label: the outer wave meets the box's
    // right edge with only its thin apex, so the full gap after it read as
    // wider than the rest of the row.
    trimRight: 1

    // Mute stays visible at full opacity; disconnected and zero volume dim.
    opacity: Audio.connected && (Audio.muted || !Audio.silent) ? 1 : Theme.label2.a

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.fadeMs
        }
    }

    // Every level and mute draw in the same box (VolumeMark), so muting
    // never changes the module's width or shoves the language label along.
    Glyph {
        Layout.fillHeight: true
        text: Audio.icon
    }

    // Left used to open pavucontrol. Everything it was opened for, the
    // outputs and each app's volume, is in the popup now, which left opens
    // (BarItem.popupButton).
    actions: ({
            [Qt.RightButton]: () => Audio.toggleMute()
        })

    scrolls: true
    Accessible.onScrollUpAction: scrollUp()
    Accessible.onScrollDownAction: scrollDown()
    onScrollUp: root.adjustVolume(true)
    onScrollDown: root.adjustVolume(false)

    property bool feedbackVisible: false

    // Keep visibility steady when restarting the hide timer for another notch.
    function adjustVolume(up: bool): void {
        Audio.step(up);
        if (Audio.connected && OpenPopup.owner === null && !root.pillDragging) {
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
        popup: AudioLevelPopup {}
    }
}

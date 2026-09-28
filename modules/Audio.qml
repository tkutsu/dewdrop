import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// custom/audio. Scroll is Audio.step, which the popup shares.
//
// One glyph, and the level only as the number of waves coming off it — the
// way the menu bar's sound item does it. A dial or a number for volume was
// tried twice (a ring round the icon, then a pill whose outline was the
// gauge) and both were a whole island for a figure the ears already know.
BarItem {
    id: root

    // The level the waves only hint at; which device is the popup's to say.
    tooltip: !Audio.connected ? "No output" : Audio.muted ? "Muted" : `Volume ${Audio.volume}%`
    popup: AudioPopup {}
    // Nothing to play through — no speaker, no headphones in the jack — is
    // nothing to set a volume on either, so it waits in the drawer until an
    // output turns up.
    quiet: !Audio.connected

    // Off is dim, the same way a module that has nothing to say yet is:
    // muted, or no sink to play through. The glyph already changes for
    // both; the dim is what makes the change readable from across the bar.
    opacity: Audio.connected && !Audio.silent ? 1 : Theme.dimOpacity

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.fadeMs
        }
    }

    // As wide as the widest icon it can show, whichever it is showing. Every
    // glyph on the bar is laid out on its ink, and a speaker with no waves is
    // narrower than one with two, so the module would otherwise grow and
    // shrink with the level and shove the language label along. The speaker
    // sits against the left edge and the waves come and go on its right, the
    // way they do off the menu bar's sound item.
    Item {
        Layout.fillHeight: true
        implicitWidth: Math.max(widest.implicitWidth, widestMuted.implicitWidth)

        Glyph {
            // A pixel towards the language label: the speaker's mouth carries
            // a column of faint anti-aliasing the ink box counts and the eye
            // does not, so on the box's own left edge it read a pixel too far
            // from its neighbour on the right.
            x: 1
            height: parent.height
            text: Audio.icon
        }

        // The rulers. Drawn at no opacity rather than hidden, because a hidden
        // glyph is never grabbed and measured (see BarText) and would report
        // the font's own guess at its width instead of its pixels.
        Glyph {
            id: widest
            text: Theme.glyph.volHigh
            opacity: 0
        }
        Glyph {
            id: widestMuted
            text: Theme.glyph.muted
            opacity: 0
        }
    }

    // Left used to open pavucontrol. Everything it was opened for, the
    // outputs and each app's volume, is in the popup now, which left opens
    // (BarItem.popupButton).
    actions: ({
            [Qt.RightButton]: () => Audio.toggleMute()
        })

    onScrollUp: Audio.step(true)
    onScrollDown: Audio.step(false)
}

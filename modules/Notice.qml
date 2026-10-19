import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import qs
import qs.components
import qs.services

// A notification as it arrives: who sent it and one line of what it said, on a
// pill of its own that comes out of the clock, or the timer beside it,
// folding back into that pill once it has been seen.
//
// The notification itself stays in the centre after this has folded away; this
// is the moment of arrival and nothing after it (see services/Notifications.qml).
BarItem {
    id: root
    name: root.kept.line || "Notification"
    textPress: true

    readonly property var entry: Notifications.latest

    // What the notice says (its line, icon and count), kept as it was while
    // it is drawn back into the clock or timer. Letting go of a notice can close its
    // notification (a fleeting one expires on the spot), which empties the
    // entry and zeroes the count the moment it starts to go.
    //
    // `current` is null unless there is a notice up to read, and `kept` only
    // ever takes it when it is not. A Binding with a `when` did this before
    // and blanked the line anyway: its value and its condition both hung off
    // the entry going null, and Qt re-evaluated the value first.
    readonly property var current: Notifications.showing && entry ? {
        line: line,
        key: Notifications.keyOf(entry),
        picture: picture.isIcon ? picture.source : Notifications.pictureOf(entry),
        burst: Notifications.burst
    } : null
    property var kept: ({ line: "", key: "", picture: "", burst: 0 })

    onCurrentChanged: if (current)
        kept = current

    // What goes on the line: the summary, and the body after it when there is
    // room. A sender with no summary is rare but legal, and falls back to the
    // body alone, then to its own name.
    readonly property string line: {
        if (!entry)
            return "";
        const summary = Notifications.plain(entry.summary);
        const body = Notifications.plain(entry.body);
        const head = summary || entry.appName;
        return body && body !== head ? head + "  ·  " + body : head;
    }

    // How wide the whole notice may get, which the bar sets from the room
    // between the clock (or the timer beside it) and the right pill (or the
    // recording pill beside that). The line takes whatever the icon,
    // the count and the padding leave of it, and elides past that.
    property int room: 0

    // Comes out of the clock or timer and is drawn back into it; the bar draws the
    // pill off `reveal` (see Bar.drop), and nothing folds.
    stowed: !Notifications.showing
    folds: false
    spacing: Theme.appIconGap + 4
    readonly property bool sliding: pill?.slidesContent ?? false
    readonly property real glassWidth: sliding ? pill.foldBox.z : width
    readonly property real glassLeft: sliding ? pill.foldBox.x : 0
    readonly property real iconInset: Math.min(padLeft, Math.max(0, (glassWidth - bell.width) / 2))
    property Item mergeCandidate: null
    property Item mergedIcon: null
    readonly property MediaIconHandoff iconHandoff: MediaIconHandoff {
        source: bell
        target: root.mergedIcon
        reveal: root.reveal
        restingX: root.sliding
            ? root.glassLeft + root.glassWidth - root.iconInset - bell.width - root.padLeft - bell.x : 0
    }
    // Keep the destination through the round trip, even while its slot is empty.
    onStowedChanged: if (!stowed)
        mergedIcon = mergeCandidate
    Component.onCompleted: if (!stowed)
        mergedIcon = mergeCandidate

    // The sender uses the same fade and scale as an ordinary bar module.
    readonly property bool senderShown: !stowed && (!sliding || reveal > 0.38
        && glassWidth >= iconInset + bell.width + spacing + (icon.visible ? icon.width : 0) + padRight)
    property real senderInk: senderShown ? 1 : 0
    Behavior on senderInk {
        onTargetValueChanged: {
            const entering = targetValue === 1;
            senderPause.duration = entering && !Theme.reduceMotion ? Theme.moduleOpenMs - Theme.moduleEnterMs : 0;
            senderTween.duration = entering ? Theme.moduleEnterMs : Theme.moduleExitMs;
            senderTween.easing.type = entering ? Easing.OutCubic : Easing.InOutCubic;
        }
        SequentialAnimation {
            PauseAnimation { id: senderPause }
            NumberAnimation { id: senderTween }
        }
    }

    // The pointer resting on it keeps it up — see Notifications.held.
    onContainsMouseChanged: Notifications.held = containsMouse

    // Its picture stands for the sender when it is a mark rather than
    // content, as on its card in the centre.
    NotificationPicture {
        id: picture
        notification: root.entry
    }

    AppIcon {
        id: icon
        visible: hasIcon
        scale: Theme.moduleScale(root.senderInk)
        Layout.fillHeight: true
        windowClass: root.kept.key
        source: root.kept.picture
        urgent: Notifications.urgent
        fallbackGlyph: Theme.glyph.notif
        opacity: Theme.moduleOpacity(root.senderInk)
        transform: Translate { x: root.glassLeft + root.iconInset - root.padLeft }
    }

    Item {
        id: bodyRoom
        Layout.fillHeight: true
        implicitWidth: body.implicitWidth
        transform: Translate { x: root.glassLeft + root.iconInset - root.padLeft }

        Marquee {
            id: body
            width: Math.max(0, Math.min(implicitWidth * (root.sliding ? root.pill.textReveal : 1),
                root.glassWidth - root.iconInset - root.padRight - bell.width - root.spacing
                - (icon.visible ? icon.width + root.spacing : 0)))
            height: parent.height
            contentWidth: parts.implicitWidth
            active: true
            paused: true

            RowLayout {
                id: parts
                width: implicitWidth
                height: parent.height
                spacing: root.spacing

                BarText {
                    Layout.fillHeight: true
                    text: root.kept.line
                    maxWidth: Math.max(1, root.room - root.padLeft - root.padRight
                        - bell.implicitWidth - root.spacing
                        - (icon.visible ? icon.implicitWidth + root.spacing : 0)
                        - (burst.shown ? burst.implicitWidth + root.spacing : 0))
                }

                BarText {
                    id: burst
                    readonly property bool shown: root.kept.burst > 0
                    Layout.fillHeight: true
                    visible: shown
                    text: "+" + root.kept.burst
                    color: Theme.label2
                }
            }
        }
    }

    // The bell rides the right edge until the shared media handoff takes it into the centre.
    BadgedGlyph {
        id: bell
        Layout.fillHeight: true
        glyph: Notifications.icon
        badge: Settings.badgeStyle("bell") === "hide" ? "" : Notifications.label
        dot: Settings.badgeStyle("bell") === "dot"
        underdot: Settings.badgeStyle("bell") === "underdot"
        opacity: root.mergedIcon ? 1 - root.iconHandoff.progress
            : root.sliding ? root.pill.geometry.contents(root.reveal) : 1
        transform: Translate { x: root.iconHandoff.sourceX }
    }

    // Left runs its default action, as clicking its card in the centre does
    // (Notifications.activate). One without a default opens in the centre
    // instead, scrolled to and marked there. Anything else only waves the
    // notice off, and the notification stays in the centre; right on an
    // urgent one answers it, and it goes from the centre too. Each makes way
    // for the next one waiting (Notifications.advance).
    actions: ({
            [Qt.LeftButton]: () => {
                const n = root.entry;
                if (n?.actions.some(a => a.identifier === "default"))
                    Notifications.activate(n);
                else
                    Notifications.focusOn(n);
                Notifications.dismissNotice(n);
            },
            [Qt.RightButton]: () => {
                const n = root.entry;
                const answered = n?.urgency === NotificationUrgency.Critical;
                Notifications.dismissNotice(n);
                if (answered && Notifications.list.includes(n))
                    n.dismiss();
            },
            [Qt.MiddleButton]: () => Notifications.dismissNotice(root.entry)
        })
}

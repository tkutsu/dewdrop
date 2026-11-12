import QtQuick
import QtQuick.Layouts
import qs.src.core
import qs.src.components
import qs.src.services as Services

// Idle timers live in the drawer; active central timers open into the side pill.
BarItem {
    id: root
    name: "Timers"
    settingsKey: "countdown"
    quiet: !Services.Timers.loaded
    tooltip: Services.Timers.tooltip()
    popup: TimerPopup {}

    property bool expanded: false
    property bool drawerOut: false
    property bool collapsed: false
    property real handoffProgress: 1
    property real handoffOffset: 0
    // The side pill is drawing its last icon back into this slot. It lands
    // here, with the glyph it left with, before an empty slot folds away.
    property bool landing: false
    property string landingGlyph: ""
    signal expandRequested()
    popupButton: root.collapsed && root.pill?.side === Pill.Side.Centre && Services.Timers.loaded ? Qt.NoButton : Qt.LeftButton
    actions: ({ [Qt.LeftButton]: () => root.expandRequested() })
    handedOver: root.handoffProgress < 1
    implicitWidth: Math.round(_fullWidth * _fold * root.handoffProgress)
    readonly property bool wantsExpansion: Services.Timers.loaded && root.pill?.side === Pill.Side.Centre
        && (root.showsClosed || root.drawerOut)
    readonly property int activeCount: Services.Timers.entries.filter(entry => entry.running
        && !Services.Timers.ringing.some(ring => ring.id === entry.id)).length + Services.Timers.ringing.length
    readonly property Item icon: timerIcon

    // The side pill carries the same indicator once its icon leaves this slot.
    BadgedGlyph {
        id: timerIcon
        Layout.fillHeight: true
        glyph: Services.Timers.loaded ? Services.Timers.glyph
            : (root.landing || root.stowed) && root.landingGlyph ? root.landingGlyph : Theme.glyph.timer
        badge: root.activeCount > 0 && Settings.badgeStyle("countdown") !== "hide" ? String(root.activeCount) : ""
        dot: Settings.badgeStyle("countdown") === "dot"
        underdot: Settings.badgeStyle("countdown") === "underdot"
        opacity: root.expanded ? 0 : root.handoffProgress
        transform: [
            ModuleIconScale { icon: timerIcon },
            Translate { x: root.handoffOffset }
        ]
    }
}

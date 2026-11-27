import QtQuick
import Quickshell
import qs.src.core

// A control inside a popup: a glyph, a word, or both, on a target the size of a
// row. Every button under the bar is one of these — a timer's pause, a queue
// row's move-up, "add", "undo", a preset duration — so they all read the same
// way, sit quiet until the pointer is on them, and take a press the same way.
//
// The press is taken on release inside the box. A slipped press that wanders
// off does not count, and a button standing on a row that is itself a button
// takes the press rather than letting the row have it too — "cancel the timer
// and also start it" is the bug that policy exists to prevent.
Item {
    id: root

    property string glyph: ""
    property string label: ""
    property string name: root.label
    // Drawn but not answering. A control with nothing to do right now stays
    // where it is and goes faint, rather than leaving and letting its
    // neighbours slide under a pointer already on its way to them.
    property bool live: true
    // Pressed in under the pointer, the way the bar's icons are (PressGlass).
    property bool pressFeedback: false
    // The one that asks twice: armed, it turns the bar's warning colour.
    property bool warn: false
    // Outlined, for the ones that stand on their own in a popup's foot rather
    // than in a run of controls at the end of a row.
    property bool framed: false
    // On, for an option (feels like, scan): held at the strong grey fill, and
    // a step past it under the pointer, so an option that is off never looks
    // on under the pointer about to press it. The label stays the same either
    // way; the fill is the state.
    property bool lit: false
    // A framed one is a popup header's (PopupHeader), a size down from the
    // controls on a row.
    property int glyphSize: framed ? Theme.captionSize : Theme.popupTextSize
    // Degrees the glyph is turned on its own middle; spin() runs it.
    property real glyphTurn: 0
    property int textSize: Theme.captionSize

    // Lit under the pointer or when the keys reach it (PopupRow says how).
    property bool keyed: false
    // The popup's ChoiceBlink (Popup.choice). A header's buttons (inside a
    // PopupHeader) flash on it, off and on the way a menu item does, and act
    // once the flash is over; every other button acts at once.
    property var blink: QsWindow.window?.choice ?? null
    property bool flashes: false
    property bool chosen: root.blink?.item === root
    property bool blinkOn: root.blink?.lit ?? true
    readonly property var keyPress: root.live && root.name !== "" ? () => root.press() : null
    readonly property bool hovered: root.chosen ? root.blinkOn : QsWindow.window?.keyItem ? root.keyed : hover.hovered

    signal tapped

    // Looked up once: a header's buttons stay in its header.
    Component.onCompleted: {
        for (let p = root.parent; p; p = p.parent)
            if (p.popupHeader === true) {
                root.flashes = true;
                break;
            }
    }

    // A press from the pointer, the keys or a screen reader.
    function press(): void {
        if (root.flashes && root.blink)
            root.blink.start(root, () => root.tapped());
        else
            root.tapped();
    }

    // Done, for a moment: the glyph turns to a check, so a copy says it took.
    // Asked for mid-turn, the check waits for the turn to finish.
    function confirm(): void {
        if (turning.running)
            root.confirmAfterTurn = true;
        else
            done.restart();
    }

    // One turn of the refresh arrows on the spot, for a button whose press
    // sends a request off (RefreshStamp, RetryButton), so the press always
    // shows. The arrows stand in for whatever the button showed (a warning
    // after a failed fetch) for the whole turn, and only then give way to
    // the check or warning the request brought. Reduce motion keeps it still.
    function spin(): void {
        if (Theme.reduceMotion || turning.running)
            return;
        root.turningWarn = root.warn;
        turning.start();
    }

    // What the glyph slot shows: the turning arrows, the check, or the glyph.
    readonly property string shownGlyph: turning.running ? Theme.glyph.refresh : done.running ? Theme.glyph.check : root.glyph
    property bool confirmAfterTurn: false
    property bool turningWarn: false


    Accessible.role: Accessible.Button
    Accessible.name: root.name
    Accessible.ignored: root.name === "" || !root.live
    Accessible.onPressAction: if (root.live && root.enabled && root.visible)
        root.press()

    // A run of plain controls is laid out on a fixed pitch so the columns line
    // up down a list; a framed one is as wide as what it says, and square
    // when that is only a glyph (the plus), with 10 px of air each side of
    // the words.
    implicitWidth: !framed ? 20 : label === "" ? implicitHeight : content.implicitWidth + 20
    implicitHeight: framed ? 20 : 22

    Rectangle {
        anchors.fill: parent
        visible: root.framed || root.lit || root.chosen
        radius: Theme.selectionRadius
        color: root.chosen ? (root.blinkOn ? Theme.selection : "transparent") : root.lit ? (root.hovered ? Theme.selectionLifted : Theme.selectionStrong) : root.hovered ? Theme.selection : "transparent"
        border.width: Theme.pillBorder
        border.color: Theme.stroke
    }

    // The word first and its mark after it, the way the title's plus ends
    // the header.
    Row {
        id: content

        anchors.centerIn: parent
        layoutDirection: Qt.RightToLeft
        scale: press.scale
        spacing: 5
        opacity: root.chosen ? 1 : !root.live ? 0.15 : root.hovered || root.lit ? 1 : (root.framed ? 0.7 : 0.6)

        // Beside a word the mark stands on its baseline, the way a letter
        // would; on its own it is centred.
        Glyph {
            visible: root.glyph !== ""
            text: root.shownGlyph
            fontSize: root.glyphSize
            turn: root.glyphTurn
            implicitHeight: root.height
            color: (turning.running ? root.turningWarn : root.warn) ? Theme.warn : Theme.fg
            inkBase: word.visible ? word.y + word.baselineOffset : NaN
        }

        // Whole pixels wide, so the mark after it lands on whole pixels too
        // rather than smeared across two columns.
        PopupText {
            id: word
            width: Math.round(implicitWidth)
            anchors.verticalCenter: parent.verticalCenter
            visible: root.label !== ""
            text: root.label
            color: root.warn ? Theme.warn : Theme.fg
            font.pixelSize: root.textSize
        }
    }

    Timer {
        id: done
        interval: 1200
    }

    NumberAnimation {
        id: turning
        target: root
        property: "glyphTurn"
        from: 0
        to: 360
        duration: Theme.spinMs
        easing.type: Easing.InOutCubic
        onFinished: if (root.confirmAfterTurn) {
            root.confirmAfterTurn = false;
            done.restart();
        }
    }

    HoverHandler {
        id: hover
    }

    TapHandler {
        id: tap
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: if (root.live)
            root.press()
    }

    PressGlass {
        id: press
        icon: content
        area: tap
        textPress: root.label !== ""
        down: root.pressFeedback && root.live && tap.pressed
    }
}

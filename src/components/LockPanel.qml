pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.src.core
import qs.src.services

// The lock screen's glass: the date and time, the weather, what notified
// while away, and the password. Lock Screen settings say which of the first
// three show; the field is always there.
//
// Frosted like a popup, but the blur is its own: nothing sits under a lock
// surface for the compositor to blur, so this blurs `backdrop`, the picture
// it floats over, and follows it as the picture drifts.
Item {
    id: root

    required property Item backdrop
    // 0 to 1 as the lock comes in; the glass fades and settles with it.
    property real presence: 1

    readonly property int pad: 36
    readonly property int radius: 36
    readonly property int innerWidth: 400
    readonly property int blurPad: 48
    readonly property bool clear: !Theme.reduceTransparency

    width: root.innerWidth + root.pad * 2
    height: content.implicitHeight + root.pad * 2
    opacity: root.presence
    scale: 0.96 + 0.04 * root.presence
    visible: root.presence > 0

    // --- the glass -----------------------------------------------------------
    RectangularShadow {
        anchors.fill: glass
        radius: root.radius
        blur: 48
        offset.y: 16
        color: Qt.rgba(0, 0, 0, 0.28)
    }

    ShaderEffectSource {
        id: behind

        visible: false
        sourceItem: root.clear ? root.backdrop : null
        sourceRect: Qt.rect(root.x - root.blurPad, root.y - root.blurPad, root.width + root.blurPad * 2, root.height + root.blurPad * 2)
        width: sourceRect.width
        height: sourceRect.height
    }

    Item {
        id: shape

        visible: false
        width: behind.width
        height: behind.height
        layer.enabled: true

        Rectangle {
            x: root.blurPad
            y: root.blurPad
            width: root.width
            height: root.height
            radius: root.radius
        }
    }

    MultiEffect {
        x: -root.blurPad
        y: -root.blurPad
        width: behind.width
        height: behind.height
        visible: root.clear
        source: behind
        // `behind` brings its own margin; padding again would stretch the
        // mask over the larger box.
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        // Comes up with the glass, which also keeps the blur from being set
        // once over a picture that has not landed yet.
        blur: root.presence
        // Vivid and a shade down: the colour
        // behind comes through, and white on it still reads.
        saturation: 0.5
        brightness: -0.18
        maskEnabled: true
        maskSource: shape
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }

    Rectangle {
        id: glass

        anchors.fill: parent
        radius: root.radius
        // Thinner than a popup's frost, which thickens towards opaque over
        // a bright picture and greys it: here the blur is darkened instead,
        // so the fill only has to cast the wallpaper's tint.
        readonly property real luma: 0.2126 * Theme.backdrop.r + 0.7152 * Theme.backdrop.g + 0.0722 * Theme.backdrop.b
        color: root.clear ? Qt.rgba(Theme.tint.r, Theme.tint.g, Theme.tint.b, 0.2 + 0.28 * glass.luma) : Theme.solid
    }

    Rim {
        anchors.fill: parent
        radius: root.radius
    }

    // --- what is on it ------------------------------------------------------
    Column {
        id: content

        x: root.pad
        y: root.pad
        width: root.innerWidth
        spacing: 22

        // The date over the time, the way a phone's lock screen has it, and
        // the weather on the date's line, where a phone puts it.
        Column {
            id: clock

            visible: Settings.lockClock || date.visible || weather.visible
            width: parent.width
            spacing: 0

            property date now: new Date()
            // A format with seconds ticks each second; otherwise on the minute.
            readonly property int step: /s/.test(Settings.lockTimeFormat.replace(/'(?:[^']|'')*'/g, "")) ? 1000 : 60000

            Timer {
                running: clock.visible
                repeat: true
                triggeredOnStart: true
                interval: clock.step - clock.now.getTime() % clock.step + 50
                onTriggered: clock.now = new Date()
            }
            Connections {
                target: WallClock
                function onWokeUp() {
                    clock.now = new Date();
                }
            }

            // The date and the weather centred together, a gap apart, as a
            // phone's lock screen has them; wider than the glass together,
            // the weather takes a line of its own under the date.
            Item {
                id: dateline

                readonly property int gap: 12
                readonly property bool both: date.visible && weather.visible
                readonly property real dateWidth: date.visible ? date.implicitWidth : 0
                readonly property real weatherWidth: weather.visible ? weather.implicitWidth : 0
                readonly property real lineWidth: dateline.dateWidth + (dateline.both ? dateline.gap : 0) + dateline.weatherWidth
                readonly property bool stacked: dateline.both && dateline.lineWidth > dateline.width
                readonly property real lineX: Math.round((dateline.width - dateline.lineWidth) / 2)

                width: parent.width
                height: dateline.stacked ? date.implicitHeight + 2 + weather.implicitHeight
                    : Math.max(date.visible ? date.implicitHeight : 0, weather.visible ? weather.implicitHeight : 0)

                // Its figures roll to the next day's, as the bar's clock does;
                // its words keep their kerning.
                RollingLine {
                    id: date

                    x: dateline.stacked ? Math.round((dateline.width - dateline.dateWidth) / 2) : dateline.lineX
                    visible: Settings.lockDateFormat !== ""
                    display: Settings.timeDisplay(clock.now, Settings.lockDateFormat, Settings.lockSmallAmPm, Settings.lockCase)
                    color: Theme.label
                    fontSize: 18
                    weight: Font.DemiBold
                }

                // This hour's weather in the date line's weather half: the icons
                // drawn as glyphs (this hour's, and the next six hours' average and
                // worst, as the bar's Forecast has them), the temperatures as
                // figures that roll to the next hour's, the rest as words.
                Row {
                    id: weather

                    x: dateline.stacked ? Math.round((dateline.width - dateline.weatherWidth) / 2)
                        : dateline.lineX + dateline.dateWidth + (dateline.both ? dateline.gap : 0)
                    y: dateline.stacked ? date.implicitHeight + 2 : 0
                    readonly property var hour: Weather.thisHour
                    readonly property var parts: Settings.lockWeatherFormat.split(/(\{(?:icon|avgicon|worsticon|temp|avgtemp|high|low)\})/).filter(part => part !== "")
                    readonly property var icons: ({
                            "{icon}": weather.hour,
                            "{avgicon}": Weather.average,
                            "{worsticon}": Weather.outlook
                        })
                    visible: Settings.lockWeatherFormat !== "" && Weather.location !== null && weather.hour !== null

                    readonly property var figures: {
                        const [high, low] = Weather.today ? Weather.highAndLow(Weather.today) : [NaN, NaN];
                        const figure = value => Number.isFinite(value) ? Weather.temperatureFigure(value) : "–";
                        return {
                            "{temp}": figure(weather.hour?.[Weather.temperatureKey]),
                            "{avgtemp}": figure(Weather.average?.[Weather.temperatureKey]),
                            "{high}": figure(high),
                            "{low}": figure(low)
                        };
                    }

                    function words(part: string): string {
                        return part.replace(/\{desc\}/g, weather.hour?.description ?? "")
                            .replace(/\{avgdesc\}/g, Weather.average?.description ?? "");
                    }

                    // Every piece is one line of the words tall, top to top, so an
                    // icon can stand on their baseline the way a letter would
                    // (PopupButton's mark does the same); centred on its box, a Nerd
                    // Font icon hangs below it.
                    Repeater {
                        model: weather.parts

                        Item {
                            id: piece

                            required property string modelData
                            readonly property bool icon: modelData in weather.icons
                            readonly property bool figure: modelData in weather.figures

                            width: piece.icon ? mark.implicitWidth : piece.figure ? degrees.implicitWidth : words.implicitWidth
                            height: words.implicitHeight

                            Glyph {
                                id: mark
                                visible: piece.icon
                                implicitHeight: piece.height
                                text: piece.icon ? weather.icons[piece.modelData]?.icon ?? "" : ""
                                fontSize: 18
                                color: Theme.label
                                inkBase: words.baselineOffset
                                // A pixel under the baseline, where the
                                // weather icons read as sitting on it.
                                nudge: 1
                            }

                            // On the words' baseline.
                            RollingText {
                                id: degrees
                                y: words.baselineOffset - degrees.baselineOffset
                                visible: piece.figure
                                asText: true
                                text: piece.figure ? weather.figures[piece.modelData] : ""
                                color: Theme.label
                                fontSize: 18
                                weight: Font.DemiBold
                            }

                            // Laid out even beside an icon or a figure, for the
                            // baseline it gives.
                            Text {
                                id: words
                                opacity: piece.icon || piece.figure ? 0 : 1
                                text: piece.icon || piece.figure ? " " : weather.words(piece.modelData)
                                color: Theme.label
                                font.family: Theme.bodyFont
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                                font.features: Theme.figures
                            }
                        }
                    }
                }
            }

            // The figures roll from one minute to the next, as the bar's
            // clock does; only the ones that change move.
            RollingText {
                id: time

                readonly property var display: Settings.timeDisplay(clock.now, Settings.lockTimeFormat, Settings.lockSmallAmPm, Settings.lockCase)

                anchors.horizontalCenter: parent.horizontalCenter
                visible: Settings.lockClock
                asText: true
                text: time.display.text
                smallRanges: time.display.smallRanges
                // A small AM/PM at two-fifths: two-thirds, the bar's, is
                // a second clock at this size.
                smallRatio: 0.4
                color: Qt.rgba(1, 1, 1, 0.92)
                fontSize: 104
                weight: Font.DemiBold
                letterSpacing: -2
            }
        }

        // The notifications and the password with none of the column's gap
        // between: the notifications bring their own under them, so it opens
        // and closes with them rather than the glass jumping by it.
        Column {
            width: parent.width

            // The latest three, newest on top; the rest as a count. One arriving
            // comes in at the top as on a phone's lock screen, faded up from a
            // touch smaller, and the others slide down to make room; one going
            // fades and shrinks first, then the rest close up with the glass.
            // Reduce Motion keeps the fades alone.
            Item {
                id: noticesBox

                width: parent.width
                height: Settings.lockNotifications && Notifications.count > 0 ? cards.contentHeight + notices.tail + content.spacing : 0
                visible: noticesBox.height > 0

                // Shrinking waits for a leaving card to fade first, so the
                // glass closes up after it has gone, never over it.
                Behavior on height {
                    id: settle

                    SequentialAnimation {
                        PauseAnimation { duration: settle.targetValue < noticesBox.height ? notices.leaveMs : 0 }
                        NumberAnimation { duration: Theme.reduceMotion ? 0 : notices.arriveMs; easing.type: Easing.OutCubic }
                    }
                }

                Column {
                    id: notices

                    readonly property int shown: 3
                    readonly property int more: Math.max(0, Notifications.count - notices.shown)
                    readonly property int arriveMs: 420
                    readonly property int leaveMs: 220
                    // The count of the rest, under the cards.
                    readonly property real tail: rest.visible ? notices.spacing + rest.implicitHeight : 0
                    width: parent.width
                    spacing: 6

                    ListView {
                        id: cards

                        width: parent.width
                        // Fills the box as it eases rather than taking its
                        // own height at once: a list cut short stops drawing
                        // the cards still fading out of it.
                        height: Math.max(0, noticesBox.height - notices.tail - content.spacing)
                        interactive: false
                        spacing: 6
                        // Diffed rather than rebuilt, so only the cards that came or
                        // went move (NotificationsPopup does the same).
                        model: ScriptModel {
                            values: Settings.lockNotifications ? Notifications.list.slice(0, notices.shown) : []
                        }

                        // Held back while the others make room, so it fades into a
                        // gap rather than over the card still leaving its place.
                        add: Transition {
                            SequentialAnimation {
                                PropertyAction { properties: "opacity"; value: 0 }
                                PropertyAction { properties: "scale"; value: Theme.reduceMotion ? 1 : 0.92 }
                                PauseAnimation { duration: Theme.reduceMotion ? 0 : notices.arriveMs * 0.35 }
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; to: 1; duration: notices.arriveMs * 0.7; easing.type: Easing.OutCubic }
                                    NumberAnimation { property: "scale"; to: 1; duration: notices.arriveMs; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                                }
                            }
                        }
                        remove: Transition {
                            NumberAnimation { property: "opacity"; to: 0; duration: notices.leaveMs; easing.type: Easing.InCubic }
                            NumberAnimation { property: "scale"; to: Theme.reduceMotion ? 1 : 0.92; duration: notices.leaveMs; easing.type: Easing.InCubic }
                        }
                        // Also lands an arrival cut short by the next one, which
                        // would otherwise stay part faded.
                        addDisplaced: Transition {
                            NumberAnimation { property: "y"; duration: Theme.reduceMotion ? 0 : notices.arriveMs; easing.type: Easing.OutCubic }
                            NumberAnimation { properties: "opacity,scale"; to: 1; duration: notices.leaveMs }
                        }
                        // The rest hold their places until the leaving card has
                        // faded, then close up with the glass.
                        removeDisplaced: Transition {
                            NumberAnimation { properties: "opacity,scale"; to: 1; duration: notices.leaveMs }
                            SequentialAnimation {
                                PauseAnimation { duration: notices.leaveMs }
                                NumberAnimation { property: "y"; duration: Theme.reduceMotion ? 0 : notices.arriveMs; easing.type: Easing.OutCubic }
                            }
                        }

                        delegate: Rectangle {
                            id: card

                            required property var modelData
                            readonly property var n: card.modelData
                            readonly property bool preview: Settings.lockPreviews

                            width: cards.width
                            height: text.implicitHeight + 20
                            radius: 14
                            color: Qt.rgba(1, 1, 1, 0.07)

                            // The sender's icon, or the bell the centre draws for
                            // one without.
                            Item {
                                x: 12
                                y: 10
                                width: 20
                                height: 20

                                Image {
                                    id: icon
                                    anchors.fill: parent
                                    source: Notifications.iconFor(card.n)
                                    sourceSize: Qt.size(40, 40)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    visible: icon.status !== Image.Ready
                                    radius: 5
                                    color: Theme.selection

                                    Glyph {
                                        anchors.centerIn: parent
                                        text: Theme.glyph.notif
                                        fontSize: Theme.popupGlyphSize - 2
                                        color: Theme.label2
                                    }
                                }
                            }

                            Column {
                                id: text

                                x: 42
                                y: 10
                                width: card.width - 42 - 14
                                spacing: 1

                                Item {
                                    width: parent.width
                                    height: app.implicitHeight

                                    Text {
                                        id: app
                                        width: parent.width - ago.implicitWidth - 8
                                        text: card.n?.appName || "Notification"
                                        elide: Text.ElideRight
                                        color: Theme.label2
                                        font.family: Theme.bodyFont
                                        font.pixelSize: Theme.footnoteSize
                                        font.weight: Theme.bodyWeight
                                    }

                                    Text {
                                        id: ago
                                        anchors.right: parent.right
                                        text: card.n ? Notifications.ago(card.n, WallClock.now) : ""
                                        color: Theme.label3
                                        font.family: Theme.bodyFont
                                        font.pixelSize: Theme.footnoteSize
                                        font.weight: Theme.bodyWeight
                                    }
                                }

                                Text {
                                    width: parent.width
                                    visible: card.preview && text !== ""
                                    text: Notifications.plain(card.n?.summary)
                                    elide: Text.ElideRight
                                    color: Theme.fg
                                    font.family: Theme.bodyFont
                                    font.pixelSize: Theme.popupTextSize
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    width: parent.width
                                    visible: card.preview && text !== ""
                                    text: Notifications.plain(card.n?.body)
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    color: Theme.label2
                                    font.family: Theme.bodyFont
                                    font.pixelSize: Theme.captionSize
                                    font.weight: Theme.bodyWeight
                                }
                            }
                        }
                    }

                    Text {
                        id: rest

                        visible: notices.more > 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: notices.more === 1 ? "1 more notification" : `${notices.more} more notifications`
                        color: Theme.label2
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.footnoteSize
                        font.weight: Theme.bodyWeight
                    }
                }
            }

            // The password: dots, and what to do with them.
            Column {
                width: parent.width
                spacing: 8

                Item {
                    id: field

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 280
                    height: 40

                    property real shake: 0
                    property real alarm: 0
                    transform: Translate {
                        x: field.shake
                    }

                    // The field: the capsule, its dots and its buttons, unless PIN
                    // Mode is checking by itself.
                    Item {
                        id: box

                        anchors.fill: parent
                        visible: !pin.visible

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: Qt.rgba(1, 1, 1, 0.12 + 0.06 * field.alarm)
                            border.width: 1
                            border.color: Qt.tint(Theme.stroke, Qt.rgba(Theme.failure.r, Theme.failure.g, Theme.failure.b, field.alarm))
                        }

                        // Just after the caret, which waits at the start.
                        Text {
                            x: 22
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Lock.password === ""
                            text: "Enter Password"
                            color: Theme.label2
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.popupTextSize
                            font.weight: Theme.bodyWeight
                        }

                        // The dots, cut off on the left once they run out of room.
                        Item {
                            id: well

                            x: 18
                            width: trail.x - 8 - well.x
                            height: parent.height
                            clip: true

                            PasswordDots {
                                id: dots

                                x: Math.min(0, well.width - width - caret.width - 4)
                                anchors.verticalCenter: parent.verticalCenter
                                count: Lock.password.length
                            }
                        }

                        // The field's caret, as every field draws it (Caret Shape and
                        // Animation), after the last dot. It has no text to cover.
                        TextCaret {
                            id: caret

                            parent: well
                            x: Lock.password === "" ? 0 : dots.x + dots.width + 4
                            anchors.verticalCenter: parent.verticalCenter
                            height: 18
                            textInput: QtObject {
                                readonly property string text: ""
                                readonly property int cursorPosition: 0
                                readonly property bool cursorVisible: !Lock.checking
                                readonly property bool readOnly: false
                                readonly property font font: Qt.font({ family: Theme.bodyFont, pixelSize: Theme.popupTextSize })
                            }
                        }

                        // Return as a button that keeps its place: dim with nothing
                        // to send, lit once there is, a spinner while the password
                        // is checked. (Caps Lock and the layout are in the card's
                        // corner.)
                        Row {
                            id: trail

                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26
                                height: 26

                                Rectangle {
                                    id: go

                                    readonly property bool live: Lock.password !== "" && !Lock.checking

                                    anchors.fill: parent
                                    radius: width / 2
                                    color: go.live && hover.hovered ? Theme.selectionLifted : Theme.selectionStrong
                                    opacity: Lock.checking ? 0 : go.live ? 1 : 0.4
                                    Behavior on opacity {
                                        NumberAnimation { duration: Theme.fadeMs }
                                    }

                                    Glyph {
                                        anchors.centerIn: parent
                                        text: Theme.glyph.unlock
                                        fontSize: Theme.popupGlyphSize
                                        color: Theme.fg
                                    }

                                    HoverHandler {
                                        id: hover
                                        enabled: go.live
                                    }
                                    TapHandler {
                                        enabled: go.live
                                        onTapped: Lock.submit()
                                    }
                                }

                                Spinner {
                                    anchors.centerIn: parent
                                    visible: Lock.checking
                                }
                            }
                        }
                    }

                    // PIN Mode: no field, just a line that fills a step with each
                    // key, by the length set for the password. Full, it pulses
                    // while the password is checked, then holds full in the
                    // answer's colour: green as the lock lifts, red through the
                    // shake before the field comes back for Return.
                    Item {
                        id: pin

                        property bool holding: false
                        property color answer: Theme.success
                        // How far the line has taken the answer's colour.
                        property real said: 0

                        anchors.centerIn: parent
                        width: 200
                        height: 4
                        visible: Lock.automaticReady || pin.holding

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: Qt.rgba(1, 1, 1, 0.18)
                        }

                        Rectangle {
                            id: filled

                            width: pin.holding ? pin.width : pin.width * Math.min(1, Lock.password.length / Math.max(1, Settings.lockPasswordLength))
                            height: pin.height
                            radius: height / 2
                            color: Qt.tint(Theme.fg, Qt.rgba(pin.answer.r, pin.answer.g, pin.answer.b, pin.said))

                            Behavior on width {
                                NumberAnimation { duration: Theme.reduceMotion ? 0 : 140; easing.type: Easing.OutCubic }
                            }

                            SequentialAnimation on opacity {
                                running: Lock.checking && pin.visible
                                loops: Animation.Infinite
                                onRunningChanged: if (!running) filled.opacity = 1
                                NumberAnimation { to: 0.35; duration: 450; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 450; easing.type: Easing.InOutSine }
                            }
                        }
                    }

                    SequentialAnimation {
                        id: shaking

                        NumberAnimation { target: field; property: "shake"; to: -12; duration: 50; easing.type: Easing.OutQuad }
                        NumberAnimation { target: field; property: "shake"; to: 10; duration: 80; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: field; property: "shake"; to: -7; duration: 70; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: field; property: "shake"; to: 4; duration: 60; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: field; property: "shake"; to: 0; duration: 60; easing.type: Easing.InQuad }
                    }

                    // Reduce Motion keeps the field still and lets the edge say it.
                    SequentialAnimation {
                        id: flushing

                        NumberAnimation { target: field; property: "alarm"; to: 1; duration: 80 }
                        PauseAnimation { duration: 400 }
                        NumberAnimation { target: field; property: "alarm"; to: 0; duration: 400 }
                    }

                    // Right: green at once, held while the lock fades out with it.
                    NumberAnimation {
                        id: passing

                        target: pin
                        property: "said"
                        to: 1
                        duration: 120
                        easing.type: Easing.OutCubic
                    }

                    // Wrong: red through the shake, then the field takes over with
                    // the red still on its edge, fading as the capsule's own does.
                    SequentialAnimation {
                        id: failing

                        NumberAnimation { target: pin; property: "said"; to: 1; duration: 80 }
                        PauseAnimation { duration: 480 }
                        PropertyAction { target: field; property: "alarm"; value: 1 }
                        PropertyAction { target: pin; property: "holding"; value: false }
                        PropertyAction { target: pin; property: "said"; value: 0 }
                        NumberAnimation { target: field; property: "alarm"; to: 0; duration: 400 }
                    }

                    // The line is held at once, not by the animations, which start
                    // a frame later: the password is already cleared by then.
                    function answer(colour: color, animation: var): void {
                        pin.answer = colour;
                        pin.said = 0;
                        pin.holding = true;
                        animation.restart();
                    }

                    Connections {
                        target: Lock
                        function onRejected() {
                            if (Lock.automatic)
                                field.answer(Theme.failure, failing);
                            else
                                flushing.restart();
                            if (!Theme.reduceMotion)
                                shaking.restart();
                        }
                        function onAccepted() {
                            if (Lock.automatic)
                                field.answer(Theme.success, passing);
                        }
                        // Locked again (or on the way back in): the line starts
                        // over, empty and white.
                        function onPhaseChanged() {
                            if (Lock.phase !== "cover" && Lock.phase !== "locked")
                                return;
                            passing.stop();
                            failing.stop();
                            pin.holding = false;
                            pin.said = 0;
                            field.alarm = 0;
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: Lock.message !== ""
                    text: Lock.message
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: Theme.warn
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.footnoteSize
                    font.weight: Theme.bodyWeight
                }
            }
        }
    }

    // Shift held a beat. A keyboard that types a symbol as Shift and a key
    // (a QMK symbol layer's !) holds it only for that keystroke, and the
    // capitals mark would flash with each one.
    property bool shiftHeld: false

    Timer {
        id: shiftBeat
        interval: 300
        onTriggered: root.shiftHeld = true
    }
    Connections {
        target: Lock
        function onShiftChanged() {
            root.shiftHeld = false;
            if (Lock.shift)
                shiftBeat.restart();
            else
                shiftBeat.stop();
        }
    }

    // One mark for capitals, while Caps Lock is on or Shift is held, and the
    // keyboard layout when there is more than one (a click moves to the
    // next), tucked into the card's corner, clear of its curve. Each mark is
    // a line of the layout's text tall and stands on its baseline, as a
    // letter would; centred, a Nerd Font icon sits low.
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 12
        spacing: 12

        Glyph {
            objectName: "capitals"
            visible: Lock.capsLock || root.shiftHeld
            implicitHeight: layoutName.implicitHeight
            inkBase: layoutName.baselineOffset
            text: Theme.glyph.capsLock
            fontSize: Theme.popupGlyphSize
            color: Theme.label2
        }

        Row {
            visible: Keyboard.layouts.length > 1
            spacing: 5

            Glyph {
                implicitHeight: layoutName.implicitHeight
                inkBase: layoutName.baselineOffset
                text: Theme.glyph.keyboard
                fontSize: Theme.popupGlyphSize
                color: switcher.hovered ? Theme.fg : Theme.label2
            }

            // Laid out with one layout too, for the line the marks stand on.
            Text {
                id: layoutName
                text: Keyboard.short || "EN"
                color: switcher.hovered ? Theme.fg : Theme.label2
                font.family: Theme.bodyFont
                font.pixelSize: Theme.captionSize
                font.weight: Font.DemiBold
            }

            HoverHandler {
                id: switcher
            }
            TapHandler {
                onTapped: Keyboard.next()
            }
        }
    }
}

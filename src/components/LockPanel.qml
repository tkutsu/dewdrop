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
        // Vivid and a shade down, as Apple's materials are: the colour
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

        // The date over the time, the way a phone's lock screen has it.
        Column {
            id: clock

            visible: Settings.lockClock
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

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.RichText
                text: Settings.timeMarkup(Settings.timeDisplay(clock.now, Settings.lockDateFormat, Settings.lockSmallAmPm, Settings.lockCase), font.pixelSize)
                color: Theme.label
                font.family: Theme.bodyFont
                font.pixelSize: 18
                font.weight: Font.DemiBold
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                // A small AM/PM at two-fifths: two-thirds, the bar's, is
                // a second clock at this size.
                textFormat: Text.RichText
                text: Settings.timeMarkup(Settings.timeDisplay(clock.now, Settings.lockTimeFormat, Settings.lockSmallAmPm, Settings.lockCase), font.pixelSize, 0.4)
                color: Qt.rgba(1, 1, 1, 0.92)
                font.family: Theme.bodyFont
                font.pixelSize: 104
                font.weight: Font.DemiBold
                font.letterSpacing: -2
                font.features: Theme.figures
            }
        }

        // This hour's weather in Lock Screen > Weather's format: the icons
        // drawn as glyphs (this hour's, and the next six hours' average and
        // worst, as the bar's Forecast has them), the rest as words.
        Row {
            id: weather

            readonly property var hour: Weather.thisHour
            readonly property var parts: Settings.lockWeatherFormat.split(/(\{(?:icon|avgicon|worsticon)\})/).filter(part => part !== "")
            readonly property var icons: ({
                    "{icon}": weather.hour,
                    "{avgicon}": Weather.average,
                    "{worsticon}": Weather.outlook
                })
            visible: Settings.lockWeather && Weather.location !== null && weather.hour !== null
            anchors.horizontalCenter: parent.horizontalCenter

            function words(part: string): string {
                const [high, low] = Weather.today ? Weather.highAndLow(Weather.today) : [NaN, NaN];
                const figure = value => Number.isFinite(value) ? Weather.temperatureFigure(value) : "–";
                return part.replace(/\{temp\}/g, figure(weather.hour?.[Weather.temperatureKey]))
                    .replace(/\{avgtemp\}/g, figure(Weather.average?.[Weather.temperatureKey]))
                    .replace(/\{desc\}/g, weather.hour?.description ?? "")
                    .replace(/\{high\}/g, figure(high))
                    .replace(/\{low\}/g, figure(low));
            }

            Repeater {
                model: weather.parts

                Item {
                    id: piece

                    required property string modelData
                    readonly property bool icon: modelData in weather.icons

                    anchors.verticalCenter: parent.verticalCenter
                    width: piece.icon ? mark.implicitWidth : words.implicitWidth
                    height: Math.max(mark.implicitHeight, words.implicitHeight)

                    Glyph {
                        id: mark
                        anchors.centerIn: parent
                        visible: piece.icon
                        text: piece.icon ? weather.icons[piece.modelData]?.icon ?? "" : ""
                        fontSize: Theme.glyphSize
                        color: Theme.label
                    }

                    Text {
                        id: words
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !piece.icon
                        text: piece.icon ? "" : weather.words(piece.modelData)
                        color: Theme.label
                        font.family: Theme.bodyFont
                        font.pixelSize: 15
                        font.weight: Theme.bodyWeight
                        font.features: Theme.figures
                    }
                }
            }
        }

        // The latest three, newest on top; the rest as a count.
        Column {
            id: notices

            readonly property int shown: 3
            readonly property int more: Math.max(0, Notifications.count - notices.shown)
            visible: Settings.lockNotifications && Notifications.count > 0
            width: parent.width
            spacing: 6

            Repeater {
                model: notices.visible ? Notifications.list.slice(0, notices.shown) : []

                Rectangle {
                    id: card

                    required property var modelData
                    readonly property var n: card.modelData
                    readonly property bool preview: Settings.lockPreviews

                    width: notices.width
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
                visible: notices.more > 0
                anchors.horizontalCenter: parent.horizontalCenter
                text: notices.more === 1 ? "1 more notification" : `${notices.more} more notifications`
                color: Theme.label2
                font.family: Theme.bodyFont
                font.pixelSize: Theme.footnoteSize
                font.weight: Theme.bodyWeight
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

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.12 + 0.06 * field.alarm)
                    border.width: 1
                    border.color: Qt.tint(Theme.stroke, Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, field.alarm))
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

                // Caps Lock, and Return as a button that keeps its place: dim
                // with nothing to send, lit once there is, a spinner while
                // the password is checked. (The layout is in the screen's
                // corner, LockScreen.qml.)
                Row {
                    id: trail

                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Lock.capsLock
                        text: Theme.glyph.capsLock
                        fontSize: Theme.popupGlyphSize
                        color: Theme.label2
                    }

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

                Connections {
                    target: Lock
                    function onRejected() {
                        flushing.restart();
                        if (!Theme.reduceMotion)
                            shaking.restart();
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

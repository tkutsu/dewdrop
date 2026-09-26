import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets
import qs
import qs.components
import qs.services

// The notification centre: everything being kept, as a column of cards down
// the right-hand side of the screen under the bar, the way the system's own
// centre slides out from its edge.
//
// Cards rather than rows in a panel. Each one is its own piece of the shell's
// glass — tinted fill, lit rim, shadow — floating over the desktop, so a long
// list reads as a stack of notes rather than as a window full of them, and
// the space between them is the desktop rather than more panel. The same
// reason there is no panel behind them to close: a click anywhere that is not
// a card closes the centre, and so does Escape (OverlayWindow's surface).
OverlayWindow {
    id: root

    name: "notifications"
    shown: Notifications.centreShown
    onDismissed: Notifications.centreShown = false

    // --- geometry ------------------------------------------------------------
    readonly property int panelWidth: 360
    // Concentric with the content inset below: a card's corner is its padding
    // plus the icon's own corner, the rule every nested radius here follows.
    readonly property int cardPad: 12
    readonly property int iconSize: 32
    readonly property int iconRadius: 6
    readonly property int cardRadius: cardPad + iconRadius
    readonly property int cardGap: 8
    // The sender's picture, when it sent one: a contact, a sleeve, a
    // screenshot. Square on the right of the card, as the system shows it.
    readonly property int thumbSize: 40
    // Under the bar by the same air the bar keeps off the screen's edges, and
    // in from the right edge by that air too, so the column lines up with the
    // end of the right pill above it.
    readonly property int top: Theme.barHeight + Theme.barMargin * 2
    readonly property int side: Theme.barMargin

    // In from the right-hand edge and back out past it, on the launcher's
    // clock: the same length and easing as its reveal, which is also exactly
    // how long the window outlives being closed (Linger), so the stack is off
    // screen before the surface goes. Not a fade, for the reason the launcher
    // gives — the cards' alpha is only just over the compositor's blur
    // threshold, and a fade drops the blur out from behind them partway.
    property real reveal: root.opened ? 1 : 0

    Behavior on reveal {
        NumberAnimation {
            duration: Theme.revealMs
            easing.type: Easing.OutCubic
        }
    }

    // The time the ages are written against. On the minute, like the clock:
    // "now" becoming "1m" is the finest step shown.
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Item {
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: Notifications.centreShown = false

        // The stack, shadows and all, travelling as one: from its place against
        // the right edge out past it by its own width and the shadow's room.
        // Rounded, so the text on the cards lands on whole pixels at rest.
        Item {
            id: slide

            readonly property real travel: root.panelWidth + root.side + Theme.shadowPad * 2

            x: Math.round(parent.width - root.side - root.panelWidth - Theme.shadowPad + slide.travel * (1 - root.reveal))
            width: root.panelWidth + Theme.shadowPad * 2
            height: parent.height

            Item {
                id: column

                x: Theme.shadowPad
                y: root.top
                width: root.panelWidth
                height: root.height - root.top - root.side

                // --- header ------------------------------------------------------
                // A capsule of its own, like the cards: the title, and the two
                // things that act on all of them.
                Item {
                    id: header

                    width: parent.width
                    height: 34

                    RectangularShadow {
                        anchors.fill: headerFill
                        offset.y: Theme.shadowY
                        radius: headerFill.radius
                        blur: Theme.shadowBlur
                        color: Theme.shadow
                    }

                    Rectangle {
                        id: headerFill

                        anchors.fill: parent
                        radius: height / 2
                        color: Theme.popupBg

                        Rim {
                            anchors.fill: parent
                            radius: parent.radius
                        }

                        // Clicks on the header are not clicks off the centre.
                        MouseArea {
                            anchors.fill: parent
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Notifications"
                        color: Theme.label
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.labelSize + 1
                        font.weight: Font.DemiBold
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.markInset + 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        HeaderButton {
                            glyph: Theme.glyph.dnd
                            label: "do not disturb"
                            lit: Notifications.dnd
                            onClicked: Notifications.setDnd(!Notifications.dnd)
                        }

                        HeaderButton {
                            visible: Notifications.count > 0
                            label: "clear"
                            onClicked: Notifications.clearAll()
                        }
                    }
                }

                // --- the cards ---------------------------------------------------
                ListView {
                    id: cards

                    anchors.top: header.bottom
                    anchors.topMargin: root.cardGap
                    width: parent.width
                    // As tall as what is in it, up to what the screen has left:
                    // the empty space under a short list belongs to the desktop,
                    // and a click there closes the centre like any other.
                    height: Math.min(contentHeight, parent.height - header.height - root.cardGap)
                    interactive: contentHeight > height
                    // The shadows hang past the cards' edges, and clipping at the
                    // list would cut them off down the sides.
                    clip: false
                    spacing: root.cardGap
                    boundsBehavior: Flickable.StopAtBounds

                    model: Notifications.list

                    // A card arriving or leaving slides the ones below it rather
                    // than jumping them.
                    displaced: Transition {
                        NumberAnimation {
                            property: "y"
                            duration: Theme.fadeMs
                            easing.type: Easing.OutCubic
                        }
                    }

                    delegate: Card {}

                // Opened from the notice beside the clock: bring that one into
                // view. Once the rows exist rather than now, since the list is
                // built in the same pass as this.
                Component.onCompleted: Qt.callLater(() => {
                    const at = Notifications.list.indexOf(Notifications.centreFocus);
                    if (at >= 0)
                        cards.positionViewAtIndex(at, ListView.Contain);
                })
                }

                // Nothing to show: a card saying so rather than an empty column,
                // which would look like the centre failed to open.
                Item {
                    id: empty

                    anchors.top: header.bottom
                    anchors.topMargin: root.cardGap
                    width: parent.width
                    height: 56
                    visible: Notifications.count === 0

                    Rectangle {
                        anchors.fill: parent
                        radius: root.cardRadius
                        color: Theme.popupBg

                        Rim {
                            anchors.fill: parent
                            radius: parent.radius
                        }

                        MouseArea {
                            anchors.fill: parent
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: Notifications.dnd ? "No notifications · do not disturb is on" : "No notifications"
                        color: Theme.label3
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.popupTextSize
                    }
                }
            }
        }
    }

    // One of the header's two controls: a word, and a glyph before it when it
    // has one, on a capsule that lights while the thing it controls is on.
    component HeaderButton: Rectangle {
        id: button

        property string glyph: ""
        property string label: ""
        property bool lit: false
        signal clicked

        width: buttonRow.implicitWidth + 20
        height: 26
        radius: height / 2
        color: button.lit ? Qt.rgba(1, 1, 1, 0.2) : (buttonArea.containsMouse ? Theme.selection : "transparent")

        Row {
            id: buttonRow

            anchors.centerIn: parent
            spacing: 5

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: button.glyph !== ""
                text: button.glyph
                color: button.lit ? Theme.label : Theme.label2
                font.family: Theme.glyphFont
                font.pixelSize: Theme.labelSize
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: button.label
                color: button.lit || buttonArea.containsMouse ? Theme.label : Theme.label2
                font.family: Theme.bodyFont
                font.pixelSize: Theme.popupTextSize
            }
        }

        MouseArea {
            id: buttonArea

            anchors.fill: parent
            hoverEnabled: true
            onClicked: button.clicked()
        }
    }

    // One notification.
    component Card: Item {
        id: card

        required property var modelData
        readonly property Notification n: modelData
        readonly property var buttons: Notifications.buttons(card.n)
        readonly property string icon: Notifications.iconFor(card.n)
        // A picture of its own — a contact, a sleeve, a screenshot. Not the
        // sender's icon again: a sender that names only an icon gets it
        // handed back here as the image too, and the card would show the same
        // logo at both ends.
        readonly property string image: {
            const url = card.n ? Notifications.url(card.n.image) : "";
            return url.startsWith("image://icon/") || url === card.icon ? "" : url;
        }

        width: ListView.view.width
        height: content.implicitHeight + root.cardPad * 2

        HoverHandler {
            id: hover
        }

        RectangularShadow {
            anchors.fill: fill
            offset.y: Theme.shadowY
            radius: fill.radius
            blur: Theme.shadowBlur
            color: Theme.shadow
        }

        Rectangle {
            id: fill

            anchors.fill: parent
            radius: root.cardRadius
            color: Theme.popupBg

            // The pointer on a card is the same lighter fill any clickable
            // row gets, laid over the whole card: the card is the button. The
            // one the centre was opened on gets it in full, which is how it
            // says "this one" among the rest.
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Theme.selection
                opacity: card.n && card.n === Notifications.centreFocus ? 1 : hover.hovered ? 0.5 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.fadeMs
                    }
                }
            }

            Rim {
                anchors.fill: parent
                radius: parent.radius
            }
        }

        // Clicking the card is asking for what it is about (see
        // Notifications.activate). Also what keeps a click on a card from
        // being a click off the centre.
        MouseArea {
            anchors.fill: parent
            onClicked: Notifications.activate(card.n)
        }

        Item {
            id: content

            x: root.cardPad
            y: root.cardPad
            width: parent.width - root.cardPad * 2
            implicitHeight: Math.max(iconBox.height, text.implicitHeight, thumb.visible ? thumb.height : 0)

            // The app's icon, or a bell on a tile when it sent none.
            Item {
                id: iconBox

                width: root.iconSize
                height: root.iconSize

                IconImage {
                    id: appIcon

                    anchors.fill: parent
                    source: card.icon
                    visible: status === Image.Ready
                }

                Rectangle {
                    anchors.fill: parent
                    visible: !appIcon.visible
                    radius: root.iconRadius
                    color: Theme.selection

                    Text {
                        anchors.centerIn: parent
                        text: Theme.glyph.notifNone
                        color: Theme.label2
                        font.family: Theme.glyphFont
                        font.pixelSize: Theme.glyphSizeLarge
                    }
                }
            }

            Column {
                id: text

                x: iconBox.width + 10
                width: content.width - x - (thumb.visible ? thumb.width + 10 : 0)
                spacing: 2

                // Who, and how long ago, on one line.
                Item {
                    width: parent.width
                    height: appName.implicitHeight

                    Text {
                        id: appName

                        width: parent.width - age.implicitWidth - 8
                        text: card.n?.appName || "Notification"
                        color: Theme.label2
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.textSize
                        elide: Text.ElideRight
                    }

                    Text {
                        id: age

                        anchors.right: parent.right
                        text: card.n ? Notifications.ago(card.n, clock.date.getTime()) : ""
                        color: Theme.label3
                        font.family: Theme.bodyFont
                        font.features: Theme.figures
                        font.pixelSize: Theme.textSize
                    }
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: Notifications.plain(card.n?.summary)
                    color: card.n?.urgency === NotificationUrgency.Critical ? Theme.warn : Theme.label
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.popupTextSize
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: Notifications.plain(card.n?.body)
                    color: Theme.label2
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.popupTextSize
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    lineHeight: 1.1
                }

                // What the sender offers besides opening it: "Reply",
                // "Mark as read", "Show in folder".
                Flow {
                    width: parent.width
                    visible: card.buttons.length > 0
                    topPadding: 6
                    spacing: 6

                    Repeater {
                        model: card.buttons

                        delegate: Rectangle {
                            id: action

                            required property var modelData

                            width: actionText.implicitWidth + 20
                            height: 24
                            radius: height / 2
                            color: actionArea.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Theme.selection

                            Text {
                                id: actionText

                                anchors.centerIn: parent
                                text: action.modelData.text
                                color: Theme.label
                                font.family: Theme.bodyFont
                                font.pixelSize: Theme.textSize
                            }

                            MouseArea {
                                id: actionArea

                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: action.modelData.invoke()
                            }
                        }
                    }
                }
            }

            ClippingRectangle {
                id: thumb

                anchors.right: parent.right
                width: root.thumbSize
                height: root.thumbSize
                radius: root.iconRadius
                color: "transparent"
                visible: card.image !== "" && picture.status === Image.Ready

                Image {
                    id: picture

                    anchors.fill: parent
                    source: card.image
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: root.thumbSize * 2
                    sourceSize.height: root.thumbSize * 2
                    asynchronous: true
                }
            }
        }

        // Close, on the card's top left corner, while the pointer is on the
        // card — where the system puts it, half off the card so it reads as a
        // control on the note rather than part of what the note says.
        Rectangle {
            x: -6
            y: -6
            width: 20
            height: 20
            radius: width / 2
            visible: hover.hovered
            color: closeArea.containsMouse ? "#3a3a3a" : "#262626"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.15)

            Text {
                anchors.centerIn: parent
                text: Theme.glyph.close
                color: Theme.label
                font.family: Theme.glyphFont
                font.pixelSize: Theme.labelSize
            }

            MouseArea {
                id: closeArea

                anchors.fill: parent
                // A touch wider than it looks, since it is small and on a
                // corner.
                anchors.margins: -2
                hoverEnabled: true
                onClicked: card.n.dismiss()
            }
        }
    }
}

import QtQuick
import QtQuick.Effects
import Quickshell
import qs
import qs.components
import qs.services

// The settings page: one box in the middle of the screen, sections down the
// left and their settings on the right, the way the system's own settings
// window is laid out. Everything it changes is in Settings.qml, and saved the
// moment it changes — there is no Apply, and nothing to lose by closing it.
//
// Closed by Escape, by a click anywhere off the box (OverlayWindow's surface),
// or by the cog again.
OverlayWindow {
    id: root

    name: "settings"
    shown: Settings.shown
    onDismissed: Settings.shown = false

    // --- geometry ------------------------------------------------------------
    readonly property int boxWidth: 640
    readonly property int boxHeight: 440
    // The launcher's corner, so the two boxes in the middle of the screen
    // read as the same kind of thing.
    readonly property int boxRadius: Theme.popupRadius
    readonly property int sideWidth: 176
    readonly property int pad: 20

    property int section: 0
    readonly property var sections: [
        { name: "General", glyph: Theme.glyph.settingsGeneral },
        { name: "Bar", glyph: Theme.glyph.settingsBar },
        { name: "Paths", glyph: Theme.glyph.settingsPaths },
        { name: "Accounts", glyph: Theme.glyph.settingsAccounts }
    ]

    // Opens from its middle outwards and closes back into it, on the
    // launcher's clock. Not a fade, for the launcher's reason: the box's alpha
    // is only just over the compositor's blur threshold.
    property real reveal: root.opened ? 1 : 0

    Behavior on reveal {
        NumberAnimation {
            duration: Theme.revealMs
            easing.type: Easing.OutCubic
        }
    }

    Item {
        id: frame

        anchors.centerIn: parent
        width: root.boxWidth
        // Even, so the box stays centred on whole pixels as it opens.
        height: 2 * Math.round(root.boxHeight * root.reveal / 2)

        RectangularShadow {
            anchors.fill: glass
            offset.y: Theme.shadowY
            radius: glass.radius
            blur: Theme.shadowBlur
            color: Theme.shadow
        }

        Rectangle {
            id: glass

            anchors.fill: parent
            radius: root.boxRadius
            color: Theme.popupBg
            clip: true

            Rim {
                anchors.fill: parent
                radius: parent.radius
            }

            // The contents at their full height, held still while the box
            // opens over them.
            Item {
                id: body

                y: -Math.round((root.boxHeight - frame.height) / 2)
                width: root.boxWidth
                height: root.boxHeight
                focus: true

                Keys.onEscapePressed: Settings.shown = false

                // Clicks on the box are not clicks off it, and a click on
                // nothing in particular takes the keyboard off a text field,
                // which is what saves it.
                MouseArea {
                    anchors.fill: parent
                    onClicked: body.forceActiveFocus()
                }

                // --- sections ------------------------------------------------
                Column {
                    x: 10
                    y: root.pad - 4
                    width: root.sideWidth - 20
                    spacing: 2

                    PopupText {
                        leftPadding: 10
                        bottomPadding: 12
                        text: "Settings"
                        color: Theme.label
                        font.pixelSize: Theme.labelSize + 3
                        font.weight: Font.DemiBold
                    }

                    Repeater {
                        model: root.sections

                        delegate: Rectangle {
                            id: tab

                            required property var modelData
                            required property int index
                            readonly property bool current: root.section === tab.index

                            width: parent.width
                            height: 30
                            radius: Theme.selectionRadius
                            color: tab.current ? Qt.rgba(1, 1, 1, 0.2) : tabArea.containsMouse ? Theme.selection : "transparent"

                            Glyph {
                                x: 10
                                height: parent.height
                                text: tab.modelData.glyph
                                fontSize: Theme.popupGlyphSize
                                color: tab.current ? Theme.label : Theme.label2
                            }

                            PopupText {
                                x: 36
                                anchors.verticalCenter: parent.verticalCenter
                                text: tab.modelData.name
                                color: tab.current ? Theme.label : Theme.label2
                            }

                            MouseArea {
                                id: tabArea

                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    root.section = tab.index;
                                    body.forceActiveFocus();
                                }
                            }
                        }
                    }
                }

                // Where the file is, for anyone who would rather edit it, or
                // copy it to the next machine.
                PopupText {
                    x: 20
                    y: root.boxHeight - root.pad - height
                    width: root.sideWidth - 30
                    // The name on a line of its own, so a long folder wraps
                    // at a slash rather than through the file name.
                    text: "Saved to settings.json in\n" + Quickshell.shellDir.replace(Settings.home, "~").replace(/\//g, "/​")
                    color: Theme.label3
                    font.pixelSize: Theme.captionSize
                    wrapMode: Text.Wrap
                }

                Rectangle {
                    x: root.sideWidth
                    width: 1
                    height: parent.height
                    color: Theme.stroke
                }

                // --- the section ---------------------------------------------
                PopupText {
                    id: heading

                    x: root.sideWidth + root.pad
                    y: root.pad
                    text: root.sections[root.section].name
                    color: Theme.label
                    font.pixelSize: Theme.labelSize + 3
                    font.weight: Font.DemiBold
                }

                PopupButton {
                    anchors.right: parent.right
                    anchors.rightMargin: root.pad - 6
                    anchors.verticalCenter: heading.verticalCenter
                    glyph: Theme.glyph.close
                    onTapped: Settings.shown = false
                }

                Flickable {
                    id: page

                    x: root.sideWidth + root.pad
                    y: heading.y + heading.height + 12
                    width: root.boxWidth - x - root.pad
                    height: root.boxHeight - y - root.pad / 2
                    contentHeight: stack.implicitHeight + root.pad / 2
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    Item {
                        id: stack

                        width: page.width
                        implicitHeight: [general, bar, paths, accounts][root.section].implicitHeight

                        // --- General ---------------------------------------
                        Column {
                            id: general

                            width: parent.width
                            visible: root.section === 0

                            Line {
                                title: "24-hour clock"
                                note: Settings.clock24h ? "The bar reads 14:05" : "The bar reads 2:05 PM"

                                Switch {
                                    on: Settings.clock24h
                                    onToggled: on => Settings.set("clock24h", on)
                                }
                            }

                            Line {
                                title: "Terminal"
                                below: true
                                note: "Opens btop, yazi and your editor. It must accept --title= and -e."

                                Field {
                                    key: "terminal"
                                    placeholder: Settings.defaultTerminal
                                }
                            }
                        }

                        // --- Bar -------------------------------------------
                        Column {
                            id: bar

                            width: parent.width
                            visible: root.section === 1

                            PopupText {
                                width: parent.width
                                bottomPadding: 6
                                text: "What the bar shows. Off takes a module off the bar altogether; to keep one out of the drawer instead, middle-click it on the bar."
                                color: Theme.label2
                                font.pixelSize: Theme.captionSize
                                wrapMode: Text.Wrap
                            }

                            Repeater {
                                model: Settings.modules

                                delegate: Line {
                                    required property var modelData

                                    title: modelData.name
                                    note: modelData.note

                                    Switch {
                                        on: Settings.moduleOn(modelData.key)
                                        onToggled: on => Settings.setModule(modelData.key, on)
                                    }
                                }
                            }
                        }

                        // --- Paths -----------------------------------------
                        Column {
                            id: paths

                            width: parent.width
                            visible: root.section === 2

                            Line {
                                title: "Wallpapers"
                                below: true
                                note: "The folder the wallpaper button cycles through."

                                Field {
                                    key: "wallpaperDir"
                                    placeholder: Settings.defaultWallpaperDir
                                }
                            }

                            Line {
                                title: "Music"
                                below: true
                                note: "mpd's music_directory, where album covers are found."

                                Field {
                                    key: "musicDir"
                                    placeholder: Settings.defaultMusicDir
                                }
                            }

                            Line {
                                title: "mpd socket"
                                below: true
                                note: "mpd.conf needs a bind_to_address line with this path."

                                Field {
                                    key: "mpdSocket"
                                    placeholder: Settings.defaultMpdSocket
                                }
                            }
                        }

                        // --- Accounts --------------------------------------
                        Column {
                            id: accounts

                            width: parent.width
                            visible: root.section === 3

                            Line {
                                title: "Google"
                                note: (Google.consenting ? "Signing in…" : !Google.configured ? "Not connected" : Google.needsConsent ? "Needs reconnecting" : "Connected") + "\nMail, Tasks and the calendar's agenda. The first sign-in asks for your own Google Cloud OAuth client."

                                PopupButton {
                                    framed: true
                                    label: Google.configured ? "Reconnect" : "Connect"
                                    live: !Google.consenting
                                    onTapped: Google.reconsent()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- parts ---------------------------------------------------------------

    // One setting: what it is and a line on what it does, with its control on
    // the right — or, for a text field, underneath at full width, since a
    // path is longer than the room beside its description. A hairline under
    // each, as the system draws its lists.
    component Line: Item {
        id: line

        property string title
        property string note
        property bool below: false
        default property alias control: slot.data

        width: parent ? parent.width : 0
        implicitHeight: (line.below ? texts.implicitHeight + 8 + slot.height : Math.max(texts.implicitHeight, slot.height)) + 20

        Column {
            id: texts

            y: line.below ? 10 : Math.round((line.height - height) / 2)
            anchors.left: parent.left
            anchors.right: line.below ? parent.right : slot.left
            anchors.rightMargin: line.below ? 0 : 16
            spacing: 3

            PopupText {
                width: parent.width
                text: line.title
                color: Theme.label
                elide: Text.ElideRight
            }

            PopupText {
                width: parent.width
                visible: line.note !== ""
                text: line.note
                color: Theme.label2
                font.pixelSize: Theme.captionSize
                wrapMode: Text.Wrap
            }
        }

        Item {
            id: slot

            anchors.right: parent.right
            y: line.below ? texts.y + texts.height + 8 : Math.round((line.height - height) / 2)
            width: line.below ? line.width : childrenRect.width
            height: childrenRect.height
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.stroke
        }
    }

    // On and off. Monochrome like the rest of the shell: a lit track with a
    // dark knob for on, a faint track with a light one for off.
    component Switch: Item {
        id: toggle

        property bool on: false
        signal toggled(bool on)

        implicitWidth: 32
        implicitHeight: 18

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: toggle.on ? Qt.rgba(1, 1, 1, 0.8) : Qt.rgba(1, 1, 1, 0.15)

            Behavior on color {
                ColorAnimation {
                    duration: Theme.fadeMs
                }
            }

            Rectangle {
                y: 2
                x: toggle.on ? parent.width - width - 2 : 2
                width: parent.height - 4
                height: width
                radius: width / 2
                color: toggle.on ? Qt.rgba(0, 0, 0, 0.65) : Theme.label

                Behavior on x {
                    NumberAnimation {
                        duration: Theme.fadeMs
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: toggle.toggled(!toggle.on)
        }
    }

    // A value typed by hand. Saved when it is done with — Enter, or a click
    // anywhere else — rather than per keystroke, so the wallpaper folder is
    // not rescanned at every letter of its name. Empty means the default,
    // which shows faintly in its place.
    component Field: Rectangle {
        id: field

        property string key
        property string placeholder

        width: parent ? parent.width : 0
        implicitHeight: 26
        radius: Theme.selectionRadius
        color: Qt.rgba(0, 0, 0, 0.2)
        border.width: Theme.pillBorder
        border.color: input.activeFocus ? Qt.rgba(1, 1, 1, 0.35) : Theme.stroke

        TextInput {
            id: input

            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            text: Settings.value(field.key)
            color: Theme.fg
            selectionColor: Qt.rgba(1, 1, 1, 0.3)
            selectedTextColor: Theme.fg
            selectByMouse: true
            font.family: Theme.bodyFont
            font.pixelSize: Theme.popupTextSize

            onEditingFinished: {
                const value = input.text.trim();
                if (value !== Settings.value(field.key))
                    Settings.set(field.key, value);
            }
        }

        PopupText {
            anchors.fill: input
            verticalAlignment: Text.AlignVCenter
            visible: input.text === ""
            text: field.placeholder
            color: Theme.label3
            elide: Text.ElideRight
        }
    }
}

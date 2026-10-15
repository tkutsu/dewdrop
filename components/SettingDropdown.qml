import QtQuick
import QtQuick.Controls as Controls
import qs

// A pop-up button, as a Mac's settings have one: the chosen option on a
// raised capsule with chevrons at its end, as wide as the widest option so it
// keeps still when the pick changes. A press opens the options as a menu, the
// chosen one ticked in the column the tray's menus tick in.
Controls.ComboBox {
    id: root

    property var setting: null
    readonly property var current: root.setting?.get()

    implicitWidth: Math.min(220, Math.ceil(Math.max(sizer.implicitWidth, valueText.implicitWidth)) + leftPadding + rightPadding)
    implicitHeight: 22
    model: root.setting?.options ?? []
    textRole: "label"
    valueRole: "value"
    currentIndex: root.model.findIndex(option => option.value === root.current)
    enabled: count > 0
    Accessible.name: root.setting?.title ?? ""
    onActivated: index => root.setting.set(root.model[index].value)
    leftPadding: 10
    rightPadding: 22

    // Every option's label laid out unseen, so the button can be as wide as
    // the widest.
    Column {
        id: sizer

        opacity: 0

        Repeater {
            model: root.model

            PopupText {
                required property var modelData
                text: modelData.label
                font.pixelSize: Theme.captionSize
            }
        }
    }

    contentItem: PopupText {
        id: valueText

        text: root.currentIndex >= 0 ? root.currentText : root.setting?.placeholder ?? "No options available"
        font.pixelSize: Theme.captionSize
        color: root.enabled ? Theme.fg : Theme.label2
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Glyph {
        x: root.width - width - 6
        anchors.verticalCenter: parent.verticalCenter
        text: Theme.glyph.popUp
        fontSize: Theme.captionSize
        color: Theme.label2
    }

    // Raised the way a chosen segment is (SettingChoice), so a pick looks
    // the same in a capsule or behind a button; flat while pressed or open.
    background: Item {
        id: chrome

        readonly property bool held: root.down || root.popup.visible

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 1
            anchors.bottomMargin: -1
            radius: height / 2
            color: Theme.shadow
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            border.width: root.visualFocus ? Theme.pillBorder : 0
            border.color: Theme.outline
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: chrome.held ? Theme.selection : Theme.selectionLifted
                }
                GradientStop {
                    position: 1
                    color: chrome.held ? Theme.selection : Theme.selectionStrong
                }
            }
        }
    }

    delegate: Controls.ItemDelegate {
        id: option

        required property var modelData
        required property int index
        readonly property bool lit: root.highlightedIndex === index || option.hovered

        width: ListView.view.width
        height: 24
        hoverEnabled: true
        leftPadding: 0
        rightPadding: 10

        contentItem: Row {
            spacing: 2

            Item {
                width: 20
                height: parent.height

                Glyph {
                    anchors.centerIn: parent
                    visible: option.index === root.currentIndex
                    text: Theme.glyph.check
                    fontSize: Theme.captionSize
                    color: label.color
                }
            }

            PopupText {
                id: label

                anchors.verticalCenter: parent.verticalCenter
                text: option.modelData.label
                font.pixelSize: Theme.captionSize
                color: option.lit ? Theme.menuSelectionText : Theme.menuText
            }
        }

        background: Rectangle {
            radius: Theme.selectionRadius
            color: option.lit ? Theme.selection : "transparent"
        }
    }

    popup: Controls.Popup {
        y: root.height + 4
        width: Math.max(root.width, sizer.implicitWidth + 32 + 2 * padding)
        padding: 5
        implicitHeight: Math.min(contentItem.implicitHeight + 2 * padding, 220)
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            Controls.ScrollIndicator.vertical: Controls.ScrollIndicator {}
        }
        // Solid, not glass: it opens over the settings' own text.
        background: Rectangle {
            color: Theme.solid
            radius: Theme.menuRadius
            border.width: Theme.pillBorder
            border.color: Theme.stroke
        }
    }
}

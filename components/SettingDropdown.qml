import QtQuick
import QtQuick.Controls as Controls
import qs

// A named option selected from a scrollable dropdown.
Controls.ComboBox {
    id: root

    property var setting: null
    readonly property var current: root.setting?.get()

    implicitWidth: 180
    implicitHeight: 26
    model: root.setting?.options ?? []
    textRole: "label"
    valueRole: "value"
    currentIndex: root.model.findIndex(option => option.value === root.current)
    enabled: count > 0
    Accessible.name: root.setting?.title ?? ""
    onActivated: index => root.setting.set(root.model[index].value)
    leftPadding: 8
    rightPadding: 26

    contentItem: PopupText {
        text: root.currentIndex >= 0 ? root.currentText : root.setting?.placeholder ?? "No options available"
        font.pixelSize: Theme.captionSize
        color: root.enabled ? Theme.fg : Theme.label2
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Glyph {
        x: root.width - width - 8
        anchors.verticalCenter: parent.verticalCenter
        text: Theme.glyph.sectionOpen
        fontSize: Theme.captionSize
        color: Theme.label2
    }

    background: Rectangle {
        radius: Theme.selectionRadius + 2
        color: Theme.well
        border.width: Theme.pillBorder
        border.color: root.activeFocus ? Theme.outline : "transparent"
    }

    delegate: Controls.ItemDelegate {
        id: option
        required property var modelData
        required property int index
        width: root.width - 8
        height: 28
        highlighted: root.highlightedIndex === index
        hoverEnabled: true
        contentItem: PopupText {
            text: option.modelData.label
            font.pixelSize: Theme.captionSize
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: Theme.selectionRadius
            color: option.highlighted || option.hovered ? Theme.selectionStrong : "transparent"
        }
    }

    popup: Controls.Popup {
        y: root.height + 2
        width: root.width
        padding: 4
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 220)
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            Controls.ScrollIndicator.vertical: Controls.ScrollIndicator {}
        }
        background: Rectangle {
            color: Theme.solid
            radius: Theme.selectionRadius + 2
            border.width: Theme.pillBorder
            border.color: Theme.outline
        }
    }
}

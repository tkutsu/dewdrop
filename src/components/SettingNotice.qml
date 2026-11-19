import QtQuick
import qs.src.core

// A caution set into a settings page, above the setting it is about: a
// warning mark and a heading in the warning colour, and plain words under
// them, in a card of their own so they are read before the switch is.
//
//   { type: "notice", id, title, text }
//
// `text` takes "\n\n" between paragraphs.
Item {
    id: root

    required property var setting

    implicitHeight: card.height + 8

    Rectangle {
        id: card

        x: Theme.popupInset
        y: 4
        width: parent.width - Theme.popupInset * 2
        height: words.implicitHeight + 20
        radius: Theme.selectionRadius + 4
        color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.08)
        border.width: 1
        border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.35)

        Glyph {
            id: mark

            x: 10
            y: 10 + Math.round((heading.implicitHeight - height) / 2)
            text: Theme.glyph.warning
            fontSize: Theme.popupGlyphSize
            color: Theme.warn
        }

        Column {
            id: words

            x: mark.x + mark.width + 8
            y: 10
            width: parent.width - x - 12
            spacing: 6

            PopupText {
                id: heading

                width: parent.width
                text: root.setting.title
                wrapMode: Text.Wrap
                color: Theme.warn
                font.weight: Font.DemiBold
            }

            PopupText {
                width: parent.width
                text: root.setting.text ?? ""
                wrapMode: Text.Wrap
                font.pixelSize: Theme.captionSize
                lineHeight: 1.15
            }
        }
    }
}

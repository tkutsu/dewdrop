import QtQuick
import Quickshell
import qs
import qs.services

// The updater tooltip was two counts. The counts are already the line totals of
// a list of package names, so show the list.
Popup {
    id: root

    readonly property int shown: 14

    readonly property var entries: Updates.officialList.concat(Updates.aurList)

    Column {
        spacing: 6

        Column {
            id: list

            spacing: 3

            PopupText {
                text: Updates.pending > 0 ? `Official ${Updates.official}/${Updates.officialTotal}    AUR ${Updates.aur}/${Updates.aurTotal}` : "System up to date"
                font.weight: Font.DemiBold
            }

            Item {
                width: 1
                height: 2
                visible: root.entries.length > 0
            }

            Repeater {
                model: root.entries.slice(0, root.shown)

                delegate: PopupText {
                    required property string modelData

                    // "pkg 1.2-1 -> 1.2-2": the name is what identifies it, the
                    // versions are the detail, so they are dimmed rather than cut.
                    text: {
                        const parts = modelData.split(" ");
                        return `${parts[0]}  <font color="${Theme.label2}">${parts.slice(1).join(" ")}</font>`;
                    }
                    textFormat: Text.StyledText
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.captionSize
                }
            }

            PopupText {
                visible: root.entries.length > root.shown
                text: `… and ${root.entries.length - root.shown} more`
                opacity: 0.6
                font.pixelSize: Theme.captionSize
            }
        }

        Rectangle {
            width: Math.max(list.width, foot.width)
            height: Theme.pillBorder
            color: Theme.stroke
        }

        Row {
            id: foot

            spacing: 4

            // The same check as a right-click on the bar, where it can be
            // found. Faint while one is out, rather than queueing another.
            PopupButton {
                height: 20
                framed: true
                live: !Updates.loading

                glyph: Theme.glyph.refresh
                label: Updates.loading ? "checking…" : "refresh"
                glyphSize: Theme.captionSize
                textSize: Theme.captionSize
                onTapped: Updates.refresh()
            }

            // The system's maintenance: caches, orphans, snapshots, logs. A
            // button you have to open the popup to reach rather than a click
            // on the bar, because it removes packages without asking.
            PopupButton {
                height: 20
                framed: true

                glyph: Theme.glyph.cleanup
                label: "clean up"
                glyphSize: Theme.captionSize
                textSize: Theme.captionSize
                onTapped: Quickshell.execDetached(Settings.inTerminal([Paths.script("cleanup.sh")], "cleanup"))
            }
        }
    }
}

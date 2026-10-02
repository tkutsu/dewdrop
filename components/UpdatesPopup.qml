import QtQuick
import Quickshell
import qs
import qs.services

// The updater tooltip was two counts. The counts are already the line totals of
// a list of package names, so show the list.
Popup {
    id: root

    // Lines of packages across both sections. The AUR goes first and is
    // usually a handful, so it takes what it needs and official the rest.
    readonly property int shown: 14

    spacing: 6

    PopupHeader {
        width: Math.max(list.width, implicitWidth)
        // The list below runs from the edge, so the title does too.
        inset: 0
        title: "Updates"

        // The upgrade itself, in a terminal. Faint with nothing to take.
        PopupButton {
            framed: true
            live: Updates.pending > 0
            glyph: Theme.glyph.update
            label: "upgrade"
            onTapped: {
                OpenPopup.dismiss();
                Quickshell.execDetached([Paths.script("taskbar-update.sh")]);
            }
        }

        // The same check as a right-click on the bar, where it can be found.
        // Faint while one is out, rather than queueing another.
        PopupButton {
            framed: true
            live: !Updates.loading
            glyph: Theme.glyph.refresh
            label: Updates.loading ? "checking…" : Updates.trouble !== "" ? "retry" : "refresh"
            onTapped: Updates.retryNow()
        }

        // The system's maintenance: caches, orphans, snapshots, logs. A button
        // you have to open the popup to reach rather than a click on the bar,
        // because it removes packages without asking.
        PopupButton {
            framed: true
            glyph: Theme.glyph.cleanup
            label: "clean up"
            onTapped: Quickshell.execDetached(Settings.inTerminal([Paths.script("cleanup.sh")], "cleanup"))
        }
    }

    // One source: its count against what is installed from it, then its
    // packages. Not there at all while it has nothing waiting.
    component Section: Column {
        id: section

        property string title
        property var entries: []
        property int total
        property int limit

        visible: entries.length > 0
        spacing: 3

        PopupText {
            text: `${section.title}  <font color="${Theme.label2}">${section.entries.length}/${section.total}</font>`
            textFormat: Text.StyledText
            font.weight: Font.DemiBold
            bottomPadding: 2
        }

        Repeater {
            model: section.entries.slice(0, section.limit)

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
            visible: section.entries.length > section.limit
            text: `… and ${section.entries.length - section.limit} more`
            opacity: 0.6
            font.pixelSize: Theme.captionSize
        }
    }

    Column {
        id: list

        spacing: 9

        PopupText {
            visible: Updates.trouble !== "" || !Updates.loaded || Updates.pending === 0
            text: Updates.trouble !== "" ? Updates.trouble : !Updates.loaded ? "Checking for updates…" : "System up to date"
            color: Theme.label2
            wrapMode: Text.WordWrap
        }

        Section {
            id: aur
            title: "AUR"
            entries: Updates.aurList
            total: Updates.aurTotal
            limit: root.shown
        }

        Section {
            title: "Official"
            entries: Updates.officialList
            total: Updates.officialTotal
            limit: root.shown - Math.min(aur.entries.length, aur.limit)
        }
    }
}

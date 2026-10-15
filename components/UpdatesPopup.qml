import QtQuick
import Quickshell
import qs
import qs.services

// The updater tooltip was two counts. The counts are already the line totals of
// a list of package names, so show the list: each name with its versions at
// the right edge, AUR packages first, and the counts in the title. The title
// is the upgrade itself, its arrow where a popup keeps its plus.
Popup {
    id: root

    // Twenty lines, then one saying how many more.
    readonly property int shown: 20
    readonly property var entries: Updates.aurList.concat(Updates.officialList)
    readonly property var rows: root.entries.slice(0, root.shown).map(line => {
        const parts = line.split(" ");
        return { name: parts[0], versions: parts.slice(1).join(" ") };
    })
    readonly property int remaining: Math.max(0, root.entries.length - root.shown)

    // A list to read, as wide as Mail and Tasks; a long name gives way to its
    // versions.
    readonly property real bodyWidth: Theme.popupWideWidth

    PopupHeader {
        id: header

        width: root.bodyWidth
        // How many, and how many of those the AUR's, on the title the
        // upgrade is pressed on.
        title: Updates.pending === 0 ? "Updates"
            : `${Updates.pending} ${Updates.pending === 1 ? "Update" : "Updates"}` + (Updates.aur > 0 ? ` (${Updates.aur} AUR)` : "")
        // The upgrade itself, in a terminal; only while there is something
        // to take.
        addable: Updates.pending > 0
        addGlyph: Theme.glyph.download
        addName: "Upgrade"
        onAdd: {
            OpenPopup.dismiss();
            Quickshell.execDetached([Paths.script("taskbar-update.sh")]);
        }

        // The same check as a right-click on the bar, where it can be found.
        // Faint while one is out, rather than queueing another; the note
        // under the header says what it is doing.
        PopupButton {
            framed: true
            live: !Updates.loading
            glyph: Theme.glyph.refresh
            label: "Refresh"
            onTapped: Updates.retryNow()
        }

        // The system's maintenance: caches, orphans, snapshots, logs. A button
        // you have to open the popup to reach rather than a click on the bar,
        // because it removes packages without asking. Runs where the upgrade
        // does: a dropdown pane, or a kitty window when the dropdown is shut.
        PopupButton {
            framed: true
            glyph: Theme.glyph.cleanup
            label: "Clean Up"
            onTapped: {
                OpenPopup.dismiss();
                Quickshell.execDetached([Paths.script("dropdown-run.sh"), "cleanup", Paths.script("cleanup.sh")]);
            }
        }
    }

    PopupNote {
        width: root.bodyWidth
        visible: Updates.trouble !== "" || !Updates.loaded || Updates.loading || Updates.pending === 0
        text: Updates.trouble !== "" ? Updates.trouble : Updates.loading || !Updates.loaded ? "Checking for updates…" : "System up to date"
        warn: Updates.trouble !== ""
    }

    // A little air above and below, so the lines read as a list rather than
    // as the header running on.
    Column {
        id: list

        visible: root.rows.length > 0
        width: root.bodyWidth
        topPadding: 4
        bottomPadding: 4
        spacing: 3

        Repeater {
            model: root.rows

            delegate: Item {
                required property var modelData

                x: Theme.popupInset
                width: root.bodyWidth - Theme.popupInset * 2
                height: name.implicitHeight

                PopupText {
                    id: name

                    width: Math.min(implicitWidth, parent.width - versions.implicitWidth - 16)
                    text: modelData.name
                    elide: Text.ElideRight
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.captionSize
                }

                PopupText {
                    id: versions

                    anchors.right: parent.right
                    text: modelData.versions
                    color: Theme.label2
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.captionSize
                }
            }
        }

        PopupText {
            x: Theme.popupInset
            visible: root.remaining > 0
            text: `${root.remaining} more`
            color: Theme.label2
            font.pixelSize: Theme.captionSize
        }
    }
}

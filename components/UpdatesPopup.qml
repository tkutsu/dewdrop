import QtQuick
import Quickshell
import qs
import qs.services

// The updater tooltip was two counts. The counts are already the line totals of
// a list of package names, so show the list.
Popup {
    id: root

    // Keep the combined list short, with AUR packages first.
    readonly property int shown: 14
    readonly property var entries: Updates.aurList.concat(Updates.officialList)
    readonly property int remaining: Math.max(0, entries.length - shown)

    spacing: 10

    PopupHeader {
        id: header

        width: Math.max(list.width, footer.implicitWidth, implicitWidth)
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
        // because it removes packages without asking. Runs where the upgrade
        // does: a dropdown pane, or a kitty window when the dropdown is shut.
        PopupButton {
            framed: true
            glyph: Theme.glyph.cleanup
            label: "clean up"
            onTapped: {
                OpenPopup.dismiss();
                Quickshell.execDetached([Paths.script("dropdown-run.sh"), "cleanup", Paths.script("cleanup.sh")]);
            }
        }
    }

    Column {
        id: list

        leftPadding: Theme.popupInset
        rightPadding: Theme.popupInset
        spacing: 3

        PopupText {
            visible: Updates.trouble !== "" || !Updates.loaded || Updates.pending === 0
            text: Updates.trouble !== "" ? Updates.trouble : !Updates.loaded ? "Checking for updates…" : "System up to date"
            color: Theme.label2
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.entries.slice(0, root.shown)

            delegate: PopupText {
                required property string modelData

                // Keep package names prominent and dim their version details.
                text: {
                    const parts = modelData.split(" ");
                    return `${parts[0]}  <font color="${Theme.label2}">${parts.slice(1).join(" ")}</font>`;
                }
                textFormat: Text.StyledText
                font.family: Theme.monoFont
                font.pixelSize: Theme.captionSize
            }
        }
    }

    Item {
        id: footer

        width: header.width
        implicitWidth: (counts.visible ? counts.implicitWidth : 0) + (more.visible ? more.implicitWidth : 0) + (counts.visible && more.visible ? 12 : 0) + Theme.popupInset * 2
        implicitHeight: Math.max(counts.implicitHeight, more.implicitHeight)
        visible: counts.visible || more.visible

        PopupText {
            id: counts

            anchors.left: parent.left
            anchors.leftMargin: Theme.popupInset
            // Only the sources that have something waiting.
            visible: Updates.loaded && Updates.pending > 0
            text: [Updates.official > 0 ? `Official ${Updates.officialList.length}/${Updates.officialTotal}` : "", Updates.aur > 0 ? `AUR ${Updates.aurList.length}/${Updates.aurTotal}` : ""].filter(Boolean).join(" · ")
            color: Theme.label2
            font.pixelSize: Theme.footnoteSize
        }

        PopupText {
            id: more

            anchors.right: parent.right
            anchors.rightMargin: Theme.popupInset
            visible: root.remaining > 0
            text: `${root.remaining} more`
            color: Theme.label2
            font.pixelSize: Theme.footnoteSize
        }
    }
}

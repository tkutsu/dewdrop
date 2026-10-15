import QtQuick
import Quickshell
import Quickshell.Networking as NM
import qs
import qs.services

// The networks in range, and one click on a row to join or leave it. A tick
// on the one in use and a spinner while one is being joined; at the right
// edge a lock on a network that will ask for a password, then its signal in
// the bar's cone. Wi-Fi's switch is at the end of the title, as on the Mac,
// and NetworkManager's own editor is the row at the foot, for anything this
// is not (a right click on the bar icon opens it too).
Popup {
    id: root

    readonly property int bodyWidth: Theme.popupWidth

    // Scanning runs while the list is on screen and not otherwise.
    Component.onCompleted: Network.watchers++
    Component.onDestruction: Network.watchers--

    PopupHeader {
        width: root.bodyWidth
        title: "Network"

        SettingSwitch {
            visible: !!Network.wifi
            name: "Wi-Fi"
            checked: Network.wifiOn
            onToggled: Network.toggleWifi()
        }
    }

    // The cable, when one is plugged in. Not a thing to press: it is up
    // whenever it has a link, and the Wi-Fi list below is what changes.
    ChoiceRow {
        width: root.bodyWidth
        visible: Network.wired?.hasLink ?? false
        text: "Ethernet"
        current: Network.wiredUp

        Glyph {
            height: parent.height
            text: Theme.glyph.wired
            fontSize: Theme.popupGlyphSize
        }
    }

    PopupSection {
        width: root.bodyWidth
        visible: Network.wifiOn
        title: "Wi-Fi"
    }

    PopupNote {
        width: root.bodyWidth
        visible: !Network.wifiOn || Network.networks.length === 0
        text: !Network.wifi ? "No Wi-Fi adapter" : !Network.wifiOn ? "Wi-Fi is off" : "Looking for networks…"
    }

    Column {
        visible: Network.wifiOn

        Repeater {
            // Diffed, so a scan that only moves the figures keeps every row
            // (and the pointer on one) where it was.
            model: ScriptModel {
                values: Network.networks
            }

            delegate: ChoiceRow {
                id: row

                required property var modelData
                // Forget asks twice: it takes the password with it. Armed
                // until the pointer leaves the row.
                property bool forgetting: false
                onHoveredChanged: if (!row.hovered)
                    row.forgetting = false

                width: root.bodyWidth
                text: modelData.name
                current: modelData.connected
                busy: modelData.stateChanging
                onTapped: Network.join(row.modelData)

                // Forget, under the pointer on a network that is saved; a
                // lock on one that is not and will want a password.
                PopupButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.hovered && row.modelData.known
                    name: (row.forgetting ? "Confirm forget " : "Forget ") + row.text
                    glyph: row.forgetting ? Theme.glyph.check : Theme.glyph.close
                    glyphSize: Theme.captionSize
                    warn: row.forgetting
                    onTapped: {
                        if (row.forgetting)
                            Network.forget(row.modelData);
                        row.forgetting = !row.forgetting;
                    }
                }

                Glyph {
                    height: parent.height
                    visible: !row.modelData.known && row.modelData.security !== NM.WifiSecurityType.Open
                    text: Theme.glyph.lock
                    fontSize: Theme.popupTextSize
                    color: Theme.label2
                }

                Glyph {
                    height: parent.height
                    text: Theme.glyph.wifiStrength[Network.bars(row.modelData.signalStrength)]
                    fontSize: Theme.popupGlyphSize
                }
            }
        }
    }

    PopupSeparator {
        width: root.bodyWidth
    }

    PopupLink {
        width: root.bodyWidth
        text: "Network Settings"
        onTapped: {
            OpenPopup.dismiss();
            Quickshell.execDetached(["nm-connection-editor"]);
        }
    }
}

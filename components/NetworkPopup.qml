import QtQuick
import Quickshell
import Quickshell.Networking as NM
import qs
import qs.services

// The networks in range, and one click on a row to join or leave it. A tick
// on the one in use and a spinner while one is being joined; at the right
// edge a lock on a network that will ask for a password, then its signal in
// the bar's cone. NetworkManager's own editor is a right click on the bar icon
// away, for anything this is not.
Popup {
    id: root

    readonly property int bodyWidth: 240

    spacing: 6

    // Scanning runs while the list is on screen and not otherwise.
    Component.onCompleted: Network.watchers++
    Component.onDestruction: Network.watchers--

    PopupHeader {
        width: root.bodyWidth
        title: "Network"

        PopupButton {
            visible: !!Network.wifi
            framed: true
            glyph: Network.wifiOn ? Theme.glyph.wifiOff : Theme.glyph.wifiStrength[4]
            label: Network.wifiOn ? "turn Wi-Fi off" : "turn Wi-Fi on"
            onTapped: Network.toggleWifi()
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

    PopupText {
        width: root.bodyWidth
        visible: !Network.wifiOn || Network.networks.length === 0
        text: !Network.wifi ? "No Wi-Fi adapter" : !Network.wifiOn ? "Wi-Fi is off" : "Looking for networks…"
        color: Theme.label2
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
                    glyph: Theme.glyph.close
                    glyphSize: Theme.captionSize
                    onTapped: {
                        Network.forget(row.modelData);
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
}

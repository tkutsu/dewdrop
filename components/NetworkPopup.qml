import QtQuick
import Quickshell
import Quickshell.Networking as NM
import qs
import qs.services

// What nm-applet's menu was opened for: the networks in range, and one click
// on a row to join or leave it. Each row carries its own signal in the bar's
// cone, and the right edge says what is happening to it, or whether joining
// it will ask for a password.
Popup {
    id: root

    readonly property int bodyWidth: 240
    readonly property int rowHeight: 24
    // The cone's column, and the air between it and the name.
    readonly property int gutter: 22

    spacing: 6

    // Scanning runs while the list is on screen and not otherwise.
    Component.onCompleted: Network.watchers++
    Component.onDestruction: Network.watchers--

    function status(network): string {
        if (network.stateChanging)
            return network.connected ? "…" : "joining…";
        return "";
    }

    // The cable, when one is plugged in. Not a thing to press: it is up
    // whenever it has a link, and the Wi-Fi list below is what changes.
    PopupRow {
        width: root.bodyWidth
        height: root.rowHeight
        visible: Network.wired?.hasLink ?? false

        Glyph {
            x: Math.round((root.gutter - implicitWidth) / 2)
            height: parent.height
            text: Theme.glyph.wired
            fontSize: Theme.popupGlyphSize
        }

        PopupText {
            x: root.gutter
            anchors.verticalCenter: parent.verticalCenter
            text: "Ethernet"
        }

        Glyph {
            anchors.right: parent.right
            anchors.rightMargin: 6
            height: parent.height
            visible: Network.wiredUp
            text: Theme.glyph.check
            fontSize: Theme.popupTextSize
        }
    }

    PopupText {
        width: root.bodyWidth
        visible: !Network.wifiOn || Network.networks.length === 0
        text: !Network.wifi ? "No Wi-Fi adapter" : !Network.wifiOn ? "Wi-Fi is off" : "Looking for networks…"
        opacity: 0.6
    }

    Column {
        visible: Network.wifiOn

        Repeater {
            // Diffed, so a scan that only moves the figures keeps every row
            // (and the pointer on one) where it was.
            model: ScriptModel {
                values: Network.networks
            }

            delegate: PopupRow {
                id: row

                required property var modelData

                readonly property bool locked: !modelData.known && modelData.security !== NM.WifiSecurityType.Open

                width: root.bodyWidth
                height: root.rowHeight
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: Network.join(row.modelData)

                Glyph {
                    x: Math.round((root.gutter - implicitWidth) / 2)
                    height: parent.height
                    text: Theme.glyph.wifiStrength[Network.bars(row.modelData.signalStrength)]
                    fontSize: Theme.popupGlyphSize
                    opacity: row.modelData.connected ? 1 : 0.7
                }

                PopupText {
                    x: root.gutter
                    anchors.verticalCenter: parent.verticalCenter
                    width: trail.x - x - 6
                    elide: Text.ElideRight
                    text: row.modelData.name
                    opacity: row.modelData.connected ? 1 : 0.7
                }

                // Whichever one thing the right edge has to say: forget, under
                // the pointer on a network that is saved; what is happening to
                // it; that it is the one in use; or that it wants a password.
                Item {
                    id: trail

                    anchors.right: parent.right
                    anchors.rightMargin: forget.visible ? 0 : 6
                    width: forget.visible ? forget.width : Math.max(statusText.implicitWidth, mark.implicitWidth)
                    height: parent.height

                    PopupButton {
                        id: forget

                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.hovered && row.modelData.known
                        glyph: Theme.glyph.close
                        onTapped: {
                            root.hold(1500);
                            Network.forget(row.modelData);
                        }
                    }

                    PopupText {
                        id: statusText

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !forget.visible && text !== ""
                        text: root.status(row.modelData)
                        color: Theme.label2
                        font.pixelSize: Theme.captionSize
                    }

                    Glyph {
                        id: mark

                        anchors.right: parent.right
                        height: parent.height
                        visible: !forget.visible && !statusText.visible && (row.modelData.connected || row.locked)
                        text: row.modelData.connected ? Theme.glyph.check : Theme.glyph.lock
                        fontSize: row.modelData.connected ? Theme.popupTextSize : Theme.captionSize
                        opacity: row.modelData.connected ? 1 : 0.5
                    }
                }
            }
        }
    }

    Rectangle {
        width: root.bodyWidth
        height: Theme.pillBorder
        color: Theme.stroke
        visible: !!Network.wifi
    }

    PopupButton {
        visible: !!Network.wifi
        framed: true
        glyph: Network.wifiOn ? Theme.glyph.wifiOff : Theme.glyph.wifiStrength[4]
        label: Network.wifiOn ? "turn Wi-Fi off" : "turn Wi-Fi on"
        glyphSize: Theme.captionSize
        textSize: Theme.captionSize
        onTapped: Network.toggleWifi()
    }
}

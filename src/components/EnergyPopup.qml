import QtQuick
import Quickshell
import qs.src.core
import qs.src.services

// The energy module's popup, after macOS's Battery and Energy panes: the
// battery's charge and where the power comes from (laptops only), the energy
// mode, and how long the machine waits without input before it turns the
// display off and goes to sleep. Power Statistics (batteryCommand) is the
// header's way out, where there is a battery for it to graph.
Popup {
    id: root

    readonly property int bodyWidth: Theme.popupWidth
    readonly property bool hasBattery: Energy.battery !== null

    // A readout: its name in grey on the left, the figure on the right.
    component Line: Item {
        id: line

        property string label
        property string value
        property bool warn: false

        width: root.bodyWidth
        implicitHeight: key.implicitHeight

        PopupText {
            id: key
            x: Theme.popupInset
            text: line.label
            color: Theme.label2
        }

        PopupText {
            anchors.right: parent.right
            anchors.rightMargin: Theme.popupInset
            anchors.baseline: key.baseline
            text: line.value
            color: line.warn ? Theme.warn : Theme.fg
        }
    }

    // A wait before something happens, its lengths in a pop-up button.
    component Wait: Item {
        id: wait

        property string label
        property string key
        property var stops

        width: root.bodyWidth
        implicitHeight: menu.implicitHeight

        PopupText {
            x: Theme.popupInset
            anchors.verticalCenter: parent.verticalCenter
            text: wait.label
        }

        SettingDropdown {
            id: menu

            anchors.right: parent.right
            anchors.rightMargin: Theme.popupInset
            setting: ({
                title: wait.label,
                options: Energy.waits(wait.stops, Settings[wait.key]),
                get: () => Settings[wait.key],
                set: minutes => Settings.set(wait.key, minutes)
            })
        }
    }

    PopupHeader {
        width: root.bodyWidth
        title: root.hasBattery ? "Battery" : "Energy"

        PopupButton {
            readonly property var command: Settings.helper(Settings.batteryCommand, false)

            visible: root.hasBattery && command.length > 0
            framed: true
            glyph: Theme.glyph.openApp
            name: "Power Statistics"
            onTapped: {
                OpenPopup.dismiss();
                Quickshell.execDetached(command);
            }
        }
    }

    NeedsNote {
        width: root.bodyWidth
        feature: "Power Statistics"
        programs: root.hasBattery && Settings.batteryCommand ? [Settings.program(Settings.batteryCommand)] : []
    }

    // The battery, macOS's menu in lines: how full, from where, how long.
    Column {
        width: root.bodyWidth
        visible: root.hasBattery
        spacing: Theme.popupSpacing

        Line {
            label: "Charge"
            value: Energy.percent + "%"
            warn: Energy.low
        }

        Line {
            label: "Power Source"
            value: Energy.plugged ? "Power Adapter" : "Battery"
        }

        Line {
            visible: Energy.timeLeft !== ""
            label: Energy.charging ? "Until Full" : "Time Left"
            value: Energy.timeLeft
        }

        Line {
            visible: Energy.draw !== ""
            label: Energy.charging ? "Charging At" : "Using"
            value: Energy.draw
        }

        Line {
            visible: Energy.health >= 0
            label: "Health"
            value: Energy.health + "%"
        }

        PopupNote {
            width: root.bodyWidth
            visible: Energy.plugged && !Energy.charging && !Energy.full
            text: "Not charging"
        }
    }

    Column {
        width: root.bodyWidth

        PopupSection {
            width: root.bodyWidth
            ruled: root.hasBattery
            title: "Energy Mode"
        }

        NeedsNote {
            width: root.bodyWidth
            topPadding: Theme.popupSpacing
            feature: "Energy Mode"
            programs: ["powerprofilesctl"]
        }

        Item {
            width: root.bodyWidth
            height: mode.y + mode.height
            visible: Energy.hasModes

            SettingDropdown {
                id: mode

                x: Theme.popupInset
                y: Theme.popupSpacing
                setting: ({
                    title: "Energy mode",
                    options: Energy.modes,
                    get: () => Energy.mode,
                    set: profile => Energy.setMode(profile)
                })
            }
        }

        PopupNote {
            width: root.bodyWidth
            visible: Energy.heldBack !== ""
            topPadding: Theme.popupSpacing
            warn: true
            text: Energy.heldBack
        }
    }

    Column {
        width: root.bodyWidth
        spacing: Theme.popupSpacing

        PopupSection {
            width: root.bodyWidth
            title: "When Idle"
        }

        Wait {
            label: "Turn Display Off"
            key: "displayOffMinutes"
            stops: Energy.displayOffStops
        }

        Wait {
            label: "Sleep"
            key: "sleepMinutes"
            stops: Energy.sleepStops
        }

        PopupNote {
            width: root.bodyWidth
            visible: Caffeine.active
            text: "Paused while Caffeine is on"
        }
    }
}

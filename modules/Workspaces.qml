import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.components

// hyprland/workspaces with a taskbar: the workspace number followed by one icon
// per *app* on it, badged with a count when that app has more than one window
// there. Clicking a badged icon walks through that app's windows.
BarItem {
    id: root

    // workspace-taskbar ignore-list
    readonly property var ignored: [/^steam_app.*/, /^gamescope$/]

    // Which windows are shouting. Hyprland flags the workspace, but it flags
    // the window too, so the bar can point at the app that wants you rather
    // than at the room it is in. Gathered once for the whole strip instead of
    // per workspace: every workspace would otherwise walk the same list.
    readonly property var urgentAddresses: Hyprland.toplevels.values.filter(t => t.urgent).map(t => t.address)

    function anyUrgent(addresses) {
        return addresses.some(a => root.urgentAddresses.includes(a));
    }

    // The Hyprland dispatcher speaks Lua here (hyprland.lua drives this setup),
    // which is why these read as function calls rather than bare dispatchers.
    onScrollUp: Hyprland.dispatch('hl.dsp.focus({ workspace = "e-1" })')
    onScrollDown: Hyprland.dispatch('hl.dsp.focus({ workspace = "e+1" })')

    // One strip rather than a run of loose workspaces, because the selection is
    // drawn across it rather than by each workspace for itself.
    Item {
        id: strip

        Layout.fillHeight: true
        implicitWidth: buttons.implicitWidth

        // The workspace the mark is under. Asking the buttons which of them is
        // active keeps the mark out of the delegate, which is the whole point:
        // one mark that moves, rather than one per workspace fading in and out.
        readonly property Item selected: {
            for (const child of buttons.children)
                if (child.active === true)
                    return child;
            return null;
        }

        // The focused workspace sits on a rounded fill, the way the open item
        // on the system's menu bar does: a lighter slab inside the pill,
        // holding the numeral and its icons. It was a rule under the group
        // before that, which is a tab's idiom rather than a menu bar's.
        // Urgency is not its business — the icon of the app that wants you
        // bounces for that, wherever on the strip it is, rather than only on
        // the workspace in front of you.
        //
        // Measured off the pill's top edge, not the strip's: the strip reaches
        // past the slab into the margin the pill claims for clicks (see
        // Theme.pillTop). Sideways it takes the pill's own padding back, less
        // the inset, so its ends sit inside the pill's ends by the same air
        // it keeps off the top and bottom.
        Rectangle {
            id: mark

            readonly property int inset: Theme.markInset

            visible: strip.selected !== null
            x: strip.selected ? strip.selected.x - Theme.pillPad + mark.inset : 0
            width: strip.selected ? strip.selected.width + (Theme.pillPad - mark.inset) * 2 : 0
            y: Theme.pillTop(strip.height) + mark.inset
            height: Theme.barHeight - mark.inset * 2
            radius: height / 2
            color: Theme.selection

            // The move is the state change: it slides from the workspace you
            // left to the one you are on, at the same pace everything else on
            // the bar fades.
            Behavior on x {
                NumberAnimation {
                    duration: Theme.fadeMs
                    easing.type: Easing.InOutQuad
                }
            }

            Behavior on width {
                NumberAnimation {
                    duration: Theme.fadeMs
                    easing.type: Easing.InOutQuad
                }
            }
        }

        RowLayout {
            id: buttons

            anchors.fill: parent
            spacing: Theme.gap

            Repeater {
                model: ScriptModel {
                    // "sort-by-number": true
                    values: [...Hyprland.workspaces.values].sort((a, b) => a.id - b.id)
                }

                delegate: Item {
                    id: button

                    required property var modelData
                    required property int index
                    readonly property bool active: Hyprland.focusedWorkspace?.id === modelData.id

                    // Roman numerals for the ten workspaces of a number row. The tenth
                    // is named "0" here, which is where X goes; anything named something
                    // else keeps its name as text.
                    readonly property string numeral: {
                        const name = modelData.name;
                        if (!/^[0-9]$/.test(name))
                            return "";
                        const index = name === "0" ? 9 : Number(name) - 1;
                        return Theme.glyph.numeral[index];
                    }

                    // One entry per window class, in the order the classes first appear,
                    // so an app does not jump along the row as its windows come and go.
                    readonly property var apps: {
                        const byClass = {};
                        const order = [];
                        for (const toplevel of Hyprland.toplevels.values) {
                            if (toplevel.workspace?.id !== modelData.id)
                                continue;
                            // A window that opened since the last `hyprctl clients`
                            // refresh has an empty lastIpcObject, and every one of those
                            // used to pile into a single classless group under the
                            // fallback glyph. The Wayland app id arrives with the window
                            // itself, so it covers the gap until the IPC object catches
                            // up.
                            const cls = toplevel.lastIpcObject?.class || toplevel.wayland?.appId || "";
                            if (root.ignored.some(re => re.test(cls)))
                                continue;
                            if (!byClass[cls]) {
                                byClass[cls] = {
                                    windowClass: cls,
                                    addresses: []
                                };
                                order.push(cls);
                            }
                            byClass[cls].addresses.push(toplevel.address);
                        }
                        return order.map(cls => byClass[cls]);
                    }

                    // The fade a workspace goes under when it is not the one you
                    // are on. It is handed to the numeral and the icons rather
                    // than put on the whole button, so the count badges are left
                    // out of it: a badge is the same badge wherever it sits on
                    // this bar, and one that dimmed with its workspace would read
                    // as a different mark from the ones on the right.
                    property real dim: button.active ? 1 : Theme.idleOpacity

                    Behavior on dim {
                        NumberAnimation {
                            duration: Theme.fadeMs
                            easing.type: Easing.InOutQuad
                        }
                    }

                    Layout.fillHeight: true
                    implicitWidth: row.implicitWidth

                    MouseArea {
                        id: press
                        anchors.fill: parent
                        // The strip's left padding belongs to the first workspace, not
                        // to the strip: an item may reach past its parent as long as
                        // nothing in the chain clips, and that is what turns the corner
                        // of the screen into a click on workspace one.
                        anchors.leftMargin: button.index === 0 ? -root.padLeft : 0
                        onClicked: Hyprland.dispatch(`hl.dsp.focus({ workspace = "${button.modelData.name}" })`)
                    }

                    RowLayout {
                        id: row
                        anchors.left: parent.left
                        height: parent.height
                        spacing: Theme.appIconGap

                        BarText {
                            Layout.fillHeight: true
                            opacity: button.dim
                            text: button.numeral || button.modelData.name
                            // A numeral is a Nerd Font glyph and gets a glyph's
                            // treatment: symbol font, single weight, laid out on its ink.
                            family: button.numeral ? Theme.glyphFont : Theme.bodyFont
                            fontSize: button.numeral ? Theme.numeralSize : Theme.textSize
                            opticalCentre: button.numeral !== ""
                            tightWidth: button.numeral !== ""
                            weight: button.numeral ? Font.Normal : (button.active ? Font.DemiBold : Theme.bodyWeight)
                            color: Theme.fg

                            transform: Translate { y: numeralBounce.offset + (press.pressed ? Theme.pressDip : 0) }
                        }

                        // The fallback, and only that. Urgency belongs on the
                        // icon of the app that wants you, so the numeral moves
                        // just when the workspace is shouting and no icon on it
                        // has owned up — an ignored window, or one Hyprland
                        // flagged by workspace without flagging the window.
                        // Otherwise a shouting app would move twice over.
                        Bounce {
                            id: numeralBounce
                            running: button.modelData.urgent && !button.apps.some(a => root.anyUrgent(a.addresses))
                        }

                        Repeater {
                            // Keyed by class, so a window opening or closing
                            // anywhere on the desktop touches only the icon it
                            // belongs to. The array itself is new on every
                            // change, and a Repeater handed the array rebuilt
                            // every icon on every workspace each time: a new
                            // desktop entry lookup and a new image load per
                            // icon, for a window that was not theirs.
                            model: ScriptModel {
                                values: button.apps
                                objectProp: "windowClass"
                            }

                            delegate: AppIcon {
                                id: app

                                required property var modelData
                                required property int index

                                Layout.alignment: Qt.AlignVCenter
                                dim: button.dim
                                windowClass: modelData.windowClass
                                count: modelData.addresses.length
                                urgent: root.anyUrgent(modelData.addresses)
                                pressed: tap.pressed

                                MouseArea {
                                    id: tap
                                    anchors.fill: parent

                                    // Focusing a window switches workspace as a side
                                    // effect. Where an icon stands for several windows,
                                    // each click moves on to the next of them, so a
                                    // badged icon is a way through the whole group.
                                    onClicked: {
                                        const addresses = app.modelData.addresses;
                                        const current = Hyprland.activeToplevel?.address;
                                        const at = addresses.indexOf(current);
                                        const next = addresses[(at + 1) % addresses.length];
                                        Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${next}" })`);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

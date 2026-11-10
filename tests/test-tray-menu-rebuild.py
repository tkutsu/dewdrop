#!/usr/bin/env python3
"""A tray menu opens as a popover does, and stays up while its app replaces the rows.

Its rows come in over DBus, so the box has to open at their full height rather
than animate up to it with the rows already drawn.

Hiding is fatal. Electron rebuilds its whole DBusMenu, under new ids, on every
state change. Hiding destroys the surface while Popup's fade still sets
HyprlandWindow.opacity on it, which Hyprland answers with a protocol error that
ends the bar. Offscreen there is no compositor to object, so this asserts the
hide itself.
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path
from test_support import fixture_root

from test_support import copy_shell, shell_env

SHELL = '''import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.src.components

ShellRoot {
    FloatingWindow {
        id: host
        implicitWidth: 40
        implicitHeight: 30
        property int hides: 0
        property real fullHeight: 0
        property int ticks: 0
        property int samples: 0
        property real shortest: Infinity
        property real smallest: 1
        property real largest: 1
        property real faintest: 1

        readonly property var tray: SystemTray.items.values.find(i => i.id === "fake") ?? null

        Item { id: entry; width: 30; height: 30 }

        Loader {
            id: loader
            active: host.tray !== null
            sourceComponent: MenuPopup {
                anchorItem: entry
                handle: host.tray.menu
                anchor.rect: Qt.rect(0, 0, 30, 30)
                onVisibleChanged: if (!visible) host.hides++
            }
        }

        function row(item, name) {
            if (item.modelData && item.modelData.text === name)
                return item;
            for (const child of item.children) {
                const found = row(child, name);
                if (found) return found;
            }
            return null;
        }

        // The opening, before the app's first rebuild.
        Timer {
            interval: 10
            repeat: true
            running: host.samples < 50 && (loader.item?.opened ?? false)
            onTriggered: {
                const menu = loader.item;
                host.samples++;
                host.shortest = Math.min(host.shortest, menu.chromeItem.height);
                host.smallest = Math.min(host.smallest, menu.growY);
                host.largest = Math.max(host.largest, menu.growY);
                host.faintest = Math.min(host.faintest, menu.revealProgress);
            }
        }

        // Long enough for the app's rebuilds to finish, then read what is left.
        Timer {
            interval: 100
            running: true
            repeat: true
            onTriggered: {
                const menu = loader.item;
                host.ticks++;
                if (menu && menu.implicitHeight > host.fullHeight)
                    host.fullHeight = menu.implicitHeight;
                if (host.ticks < 35)
                    return;
                console.log(host.shortest >= menu.chromeHeight - 1
                    ? "PASS: the box opens at its full height"
                    : "FAIL: the box opened at " + host.shortest + " of " + menu.chromeHeight);
                console.log(host.smallest < 0.95 && host.largest > 1.003
                    ? "PASS: it grows and bounces like a popover"
                    : "FAIL: scale ran " + host.smallest + " to " + host.largest);
                console.log(host.faintest < 0.5
                    ? "PASS: it fades in"
                    : "FAIL: faintest " + host.faintest);
                console.log(host.hides === 0 && host.fullHeight > 0 ? "PASS: stayed up" : "FAIL: hid " + host.hides + " times");
                console.log(menu && menu.implicitHeight === host.fullHeight && host.row(menu.contentItem, "Connect")
                    ? "PASS: rows back at full height"
                    : "FAIL: height " + menu?.implicitHeight + " of " + host.fullHeight);
                Qt.quit();
            }
        }
    }
}
'''

TRAY = '''import dbus, dbus.service, dbus.mainloop.glib
from gi.repository import GLib

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
PROPS = 'org.freedesktop.DBus.Properties'
MENU = 'com.canonical.dbusmenu'
WATCHER = 'org.kde.StatusNotifierWatcher'


class Item(dbus.service.Object):
    @dbus.service.method(PROPS, in_signature='ss', out_signature='v')
    def Get(self, _iface, name):
        return self.GetAll(_iface)[name]

    @dbus.service.method(PROPS, in_signature='s', out_signature='a{sv}')
    def GetAll(self, _iface):
        return dbus.Dictionary({'Id': 'fake', 'Status': 'Active', 'IconName': 'dialog-information',
                                'Menu': dbus.ObjectPath('/com/canonical/dbusmenu')}, signature='sv')


class Menu(dbus.service.Object):
    revision = 1
    first = 100

    @dbus.service.signal(MENU, signature='ui')
    def LayoutUpdated(self, revision, parent):
        pass

    @dbus.service.method(MENU, in_signature='iias', out_signature='u(ia{sv}av)')
    def GetLayout(self, _parent, _depth, _names):
        rows = [{'label': 'Open'}, {'type': 'separator'}, {'label': 'Connect'}, {'label': 'Quit'}]
        children = dbus.Array([dbus.Struct((self.first + i, dbus.Dictionary(r, signature='sv'), dbus.Array([], signature='v')),
                                           signature='ia{sv}av', variant_level=1) for i, r in enumerate(rows)], signature='v')
        root = dbus.Struct((0, dbus.Dictionary({'children-display': 'submenu'}, signature='sv'), children), signature='ia{sv}av')
        return dbus.UInt32(self.revision), root

    @dbus.service.method(MENU, in_signature='ias', out_signature='a(ia{sv})')
    def GetGroupProperties(self, _ids, _names):
        return dbus.Array([], signature='(ia{sv})')

    @dbus.service.method(MENU, in_signature='i', out_signature='b')
    def AboutToShow(self, _id):
        return False

    @dbus.service.method(MENU, in_signature='isvu')
    def Event(self, _id, _kind, _data, _time):
        pass

    def rebuild(self):
        self.revision += 1
        self.first += 10
        self.LayoutUpdated(dbus.UInt32(self.revision), 0)
        return self.revision < 6


item = Item(bus, '/StatusNotifierItem')
menu = Menu(bus, '/com/canonical/dbusmenu')


def register():
    if not bus.name_has_owner(WATCHER):
        return True
    bus.get_object(WATCHER, '/StatusNotifierWatcher').RegisterStatusNotifierItem('/StatusNotifierItem', dbus_interface=WATCHER)
    GLib.timeout_add(1500, lambda: GLib.timeout_add(200, menu.rebuild) and False)
    return False


GLib.timeout_add(100, register)
GLib.MainLoop().run()
'''


def run(target):
    """Inside the private bus: the fake app alongside the shell."""
    env = shell_env(target, DBUS_SESSION_BUS_ADDRESS=os.environ['DBUS_SESSION_BUS_ADDRESS'], QT_NO_XDG_DESKTOP_PORTAL='1')
    tray = subprocess.Popen([sys.executable, '-I', str(target / 'fake_tray.py')])
    try:
        result = subprocess.run(['qs', '-p', str(target), '--no-color'], env=env, capture_output=True, text=True, timeout=30)
    finally:
        tray.terminate()
    output = result.stdout + result.stderr
    print(output, end='')
    assert result.returncode == 0 and output.count('PASS:') == 5 and 'FAIL:' not in output


def main():
    if len(sys.argv) > 1:
        run(Path(sys.argv[1]))
        return
    with tempfile.TemporaryDirectory(prefix='quickshell-tray-rebuild-') as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / 'shell.qml').write_text(SHELL)
        (target / 'fake_tray.py').write_text(TRAY)
        subprocess.run(['dbus-run-session', '--', sys.executable, __file__, folder], check=True, timeout=60)
    print('tray menu rebuild ok')


if __name__ == '__main__':
    main()

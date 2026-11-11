#!/usr/bin/env python3
"""Steam's tray menu leaves out the Proton and Linux Runtime rows.

Steam lists the apps it ran last, and it runs its compatibility tools under
every game. The tray hands MenuPopup a test that drops them; a separator left
with nothing above it goes too. The test is read out of Tray.qml, so this runs
the bar's own rule against rows labelled the way Steam labels them.
"""

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from test_support import ROOT, copy_shell, fixture_root, shell_env

HIDES = re.search(r'^\s*hides: entry\.isSteam \? (.+?) : null$', (ROOT / 'src/modules/Tray.qml').read_text(), re.M).group(1)

SHELL = '''import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.src.components

ShellRoot {
    FloatingWindow {
        id: host
        implicitWidth: 40
        implicitHeight: 30

        readonly property var tray: SystemTray.items.values.find(i => i.id === "fake") ?? null

        Item { id: entry; width: 30; height: 30 }

        Loader {
            id: loader
            active: host.tray !== null
            sourceComponent: MenuPopup {
                anchorItem: entry
                handle: host.tray.menu
                anchor.rect: Qt.rect(0, 0, 30, 30)
                hides: HIDES
            }
        }

        // The rows as drawn, top to bottom, a separator as "-".
        function rows(item, out) {
            if (item.modelData !== undefined && item.modelData.isSeparator !== undefined)
                out.push(item.modelData.isSeparator ? "-" : item.modelData.text);
            for (const child of item.children)
                rows(child, out);
            return out;
        }

        Timer {
            interval: 100
            running: true
            repeat: true
            property int ticks: 0
            onTriggered: {
                const menu = loader.item;
                if (++ticks < 20 && !(menu?.populated ?? false))
                    return;
                const got = menu ? host.rows(menu.contentItem, []).join("|") : "no menu";
                const want = "Paranormasight 2|-|Store";
                console.log(got === want ? "PASS: tools and the separator they left are gone" : "FAIL: rows " + got);
                Qt.quit();
            }
        }
    }
}
'''.replace('HIDES', HIDES)

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
    @dbus.service.method(MENU, in_signature='iias', out_signature='u(ia{sv}av)')
    def GetLayout(self, _parent, _depth, _names):
        rows = [{'label': 'Proton 11.0'}, {'label': 'Steam Linux Runtime 4.0'}, {'type': 'separator'},
                {'label': 'Paranormasight 2'}, {'label': 'Proton Experimental'}, {'type': 'separator'},
                {'label': 'Store'}]
        children = dbus.Array([dbus.Struct((1 + i, dbus.Dictionary(r, signature='sv'), dbus.Array([], signature='v')),
                                           signature='ia{sv}av', variant_level=1) for i, r in enumerate(rows)], signature='v')
        root = dbus.Struct((0, dbus.Dictionary({'children-display': 'submenu'}, signature='sv'), children), signature='ia{sv}av')
        return dbus.UInt32(1), root

    @dbus.service.method(MENU, in_signature='ias', out_signature='a(ia{sv})')
    def GetGroupProperties(self, _ids, _names):
        return dbus.Array([], signature='(ia{sv})')

    @dbus.service.method(MENU, in_signature='i', out_signature='b')
    def AboutToShow(self, _id):
        return False

    @dbus.service.method(MENU, in_signature='isvu')
    def Event(self, _id, _kind, _data, _time):
        pass


item = Item(bus, '/StatusNotifierItem')
menu = Menu(bus, '/com/canonical/dbusmenu')


def register():
    if not bus.name_has_owner(WATCHER):
        return True
    bus.get_object(WATCHER, '/StatusNotifierWatcher').RegisterStatusNotifierItem('/StatusNotifierItem', dbus_interface=WATCHER)
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
    assert result.returncode == 0 and output.count('PASS:') == 1 and 'FAIL:' not in output


def main():
    if len(sys.argv) > 1:
        run(Path(sys.argv[1]))
        return
    with tempfile.TemporaryDirectory(prefix='quickshell-tray-hides-') as folder:
        target = fixture_root(folder)
        copy_shell(target)
        (target / 'shell.qml').write_text(SHELL)
        (target / 'fake_tray.py').write_text(TRAY)
        subprocess.run(['dbus-run-session', '--', sys.executable, __file__, folder], check=True, timeout=60)
    print('tray menu hides ok')


if __name__ == '__main__':
    main()

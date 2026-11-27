#!/usr/bin/env python3
"""A tray app on the session bus, for the tray tests: one item whose menu
holds the rows given as JSON, each {"label": …} or {"type": "separator"}.

    fake_tray.py ROWS [--rebuild]

--rebuild renumbers the rows and announces a new layout every 200 ms,
from 1.5 s after the item registers, five times, the way an app that
rebuilds its menu on every change does.

Gio rather than dbus-python, which the system need not have.
"""

import json
import sys

from gi.repository import Gio, GLib

WATCHER = 'org.kde.StatusNotifierWatcher'
MENU = 'com.canonical.dbusmenu'
ITEM_PATH = '/StatusNotifierItem'
MENU_PATH = '/com/canonical/dbusmenu'

NODE = Gio.DBusNodeInfo.new_for_xml(f'''<node>
  <interface name="org.kde.StatusNotifierItem">
    <property name="Id" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="Menu" type="o" access="read"/>
  </interface>
  <interface name="{MENU}">
    <method name="GetLayout">
      <arg direction="in" type="i"/><arg direction="in" type="i"/><arg direction="in" type="as"/>
      <arg direction="out" type="u"/><arg direction="out" type="(ia{{sv}}av)"/>
    </method>
    <method name="GetGroupProperties">
      <arg direction="in" type="ai"/><arg direction="in" type="as"/>
      <arg direction="out" type="a(ia{{sv}})"/>
    </method>
    <method name="AboutToShow">
      <arg direction="in" type="i"/><arg direction="out" type="b"/>
    </method>
    <method name="Event">
      <arg direction="in" type="i"/><arg direction="in" type="s"/><arg direction="in" type="v"/><arg direction="in" type="u"/>
    </method>
    <signal name="LayoutUpdated"><arg type="u"/><arg type="i"/></signal>
  </interface>
</node>''')

ITEM = {'Id': GLib.Variant('s', 'fake'), 'Status': GLib.Variant('s', 'Active'),
        'IconName': GLib.Variant('s', 'dialog-information'), 'Menu': GLib.Variant('o', MENU_PATH)}

rows = json.loads(sys.argv[1])
rebuilds = '--rebuild' in sys.argv[2:]
state = {'revision': 1, 'first': 100 if rebuilds else 1}
bus = Gio.bus_get_sync(Gio.BusType.SESSION)


def item_property(_bus, _sender, _path, _iface, name):
    return ITEM[name]


def menu_call(_bus, _sender, _path, _iface, method, _args, call):
    if method == 'GetLayout':
        children = [GLib.Variant('(ia{sv}av)', (state['first'] + i, {k: GLib.Variant('s', v) for k, v in row.items()}, []))
                    for i, row in enumerate(rows)]
        root = (0, {'children-display': GLib.Variant('s', 'submenu')}, children)
        call.return_value(GLib.Variant('(u(ia{sv}av))', (state['revision'], root)))
    elif method == 'GetGroupProperties':
        call.return_value(GLib.Variant('(a(ia{sv}))', ([],)))
    elif method == 'AboutToShow':
        call.return_value(GLib.Variant('(b)', (False,)))
    else:
        call.return_value(None)


def rebuild():
    state['revision'] += 1
    state['first'] += 10
    bus.emit_signal(None, MENU_PATH, MENU, 'LayoutUpdated', GLib.Variant('(ui)', (state['revision'], 0)))
    return state['revision'] < 6


def register():
    owned = bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'NameHasOwner',
                          GLib.Variant('(s)', (WATCHER,)), None, Gio.DBusCallFlags.NONE, -1, None).unpack()[0]
    if not owned:
        return True
    bus.call_sync(WATCHER, '/StatusNotifierWatcher', WATCHER, 'RegisterStatusNotifierItem',
                  GLib.Variant('(s)', (ITEM_PATH,)), None, Gio.DBusCallFlags.NONE, -1, None)
    if rebuilds:
        GLib.timeout_add(1500, lambda: GLib.timeout_add(200, rebuild) and False)
    return False


bus.register_object(ITEM_PATH, NODE.interfaces[0], None, item_property, None)
bus.register_object(MENU_PATH, NODE.interfaces[1], menu_call, None, None)
GLib.timeout_add(100, register)
GLib.MainLoop().run()

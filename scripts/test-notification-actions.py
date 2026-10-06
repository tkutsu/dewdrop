#!/usr/bin/env python3
"""Check real NotificationAction dispatch on a private D-Bus session."""

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


CLIENT = r'''
import subprocess
import sys
import time
from gi.repository import Gio, GLib

target = sys.argv[1]
shell = subprocess.Popen(["qs", "-p", target, "--no-color"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
passed = False
try:
    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    def call(method, parameters=None):
        return connection.call_sync("org.freedesktop.Notifications", "/org/freedesktop/Notifications",
            "org.freedesktop.Notifications", method, parameters, None, Gio.DBusCallFlags.NONE, 1000, None)
    deadline = time.monotonic() + 3
    while True:
        try:
            call("GetServerInformation")
            break
        except GLib.Error:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.02)
    events = []
    connection.signal_subscribe(None, "org.freedesktop.Notifications", None,
        "/org/freedesktop/Notifications", None, Gio.DBusSignalFlags.NONE,
        lambda conn, sender, path, interface, member, parameters: events.append((member, parameters.unpack())))
    # "none" is a click on a notification with no actions: it goes to the
    # sender, which here has no window or desktop entry, and is cleared.
    for identifier, resident in (("default", False), ("reply", False), ("default", True), ("reply", True), ("none", False)):
        actions = [] if identifier == "none" else ["default", " ", "reply", "Reply"]
        notification_id = call("Notify", GLib.Variant("(susssasa{sv}i)",
            ("Fixture", 0, "", "Title", "Body", actions, {"resident": GLib.Variant("b", resident)}, 0))).unpack()[0]
        result = subprocess.run(["qs", "ipc", "-p", target, "call", "fixture", "invoke", identifier],
            capture_output=True, text=True, timeout=3)
        assert result.returncode == 0, result.stdout + result.stderr
        deadline = time.monotonic() + 2
        expected = [("NotificationClosed", (notification_id, 2))]
        if identifier != "none":
            expected.insert(0, ("ActionInvoked", (notification_id, identifier)))
        while events[-len(expected):] != expected and time.monotonic() < deadline:
            while GLib.MainContext.default().pending():
                GLib.MainContext.default().iteration(False)
            time.sleep(0.01)
        assert events[-len(expected):] == expected, (identifier, resident, events)
        remaining = subprocess.check_output(["qs", "ipc", "-p", target, "call", "fixture", "count"], text=True, timeout=3)
        assert remaining.strip() == "0", remaining
    assert len(events) == 9, events
    passed = True
    print("PASS: clicks and action buttons dispatch once and clear resident and non-resident notifications")
finally:
    shell.terminate()
    output, _ = shell.communicate(timeout=3)
    if not passed:
        print(output)
'''


def main():
    source = (ROOT / "services/Notifications.qml").read_text()
    functions = source[source.index("    function activate(n)"):source.index("    // --- presentation helpers")]
    with tempfile.TemporaryDirectory(prefix="quickshell-notification-actions-") as folder:
        target = Path(folder)
        (target / "services").mkdir()
        (target / "services/Notifications.qml").write_text('''pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import qs.services
Singleton {
    id: root
    readonly property var list: [...server.trackedNotifications.values]
    NotificationServer {
        id: server
        actionsSupported: true
        onNotification: n => n.tracked = true
    }
''' + functions + "}\n")
        (target / "services/OpenPopup.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { function dismiss() {} }\n')
        (target / "shell.qml").write_text('''import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
    property var notificationService: Notifications
    IpcHandler {
        target: "fixture"
        // The default action and none are a click on the card; the others
        // are its buttons, which never include the default.
        function invoke(identifier: string): void {
            const notification = Notifications.list[0];
            const buttons = Notifications.buttons(notification);
            if (buttons.some(a => a.identifier === "default"))
                throw Error("The default action has a button");
            if (identifier === "default" || identifier === "none")
                return Notifications.activate(notification);
            const action = buttons.find(a => a.identifier === identifier);
            if (!action)
                throw Error("Action is missing from notification buttons");
            Notifications.run(action, notification);
        }
        function count(): int { return Notifications.list.length; }
    }
}
''')
        (target / "client.py").write_text(CLIENT)
        # No service directories: this bus cannot auto-start desktop services.
        (target / "bus.conf").write_text('''<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow own="*"/>
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
  </policy>
</busconfig>''')
        runtime = target / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime))
        for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(key, None)
        return subprocess.run(["dbus-run-session", "--config-file", str(target / "bus.conf"), "--", "/usr/bin/python3", str(target / "client.py"), str(target)], env=env, timeout=15).returncode


if __name__ == "__main__":
    raise SystemExit(main())

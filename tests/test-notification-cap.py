#!/usr/bin/env python3
"""Past the ceiling on kept notifications the oldest expire, critical ones aside."""

import os
from pathlib import Path
from test_support import fixture_root
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


CLIENT = r'''
import json
from pathlib import Path
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

    def ipc(*args):
        result = subprocess.run(["qs", "ipc", "-p", target, "call", "fixture", *args], capture_output=True, text=True, timeout=3)
        assert result.returncode == 0, result.stdout + result.stderr
        return result.stdout.strip()

    def send(summary, urgency=1, app="Fixture", timeout=-1, actions=(), transient=False):
        hints = {"urgency": GLib.Variant("y", urgency)}
        if transient:
            hints["transient"] = GLib.Variant("b", True)
        return call("Notify", GLib.Variant("(susssasa{sv}i)", (app, 0, "", summary, "", list(actions), hints, timeout))).unpack()[0]

    def expect(**wanted):
        deadline = time.monotonic() + 2
        while True:
            state = json.loads(ipc("state"))
            if all(state[k] == v for k, v in wanted.items()):
                return state
            if time.monotonic() >= deadline:
                raise AssertionError((wanted, state))
            time.sleep(0.02)

    # A critical one first, then normal ones past the ceiling of three.
    send("Urgent", urgency=2)
    for summary in ("One", "Two", "Three", "Four"):
        send(summary)
    state = expect(kept=["Four", "Three", "Urgent"])

    # Still three, and the critical one is still there, however many come.
    send("Five")
    expect(kept=["Five", "Four", "Urgent"])

    passed = True
    print("PASS: past the ceiling the oldest expire, and a critical one stays")
finally:
    shell.terminate()
    output, _ = shell.communicate(timeout=3)
    if not passed:
        print(output)
'''


SHELL = r'''import Quickshell
import Quickshell.Io
import qs.src.core
import qs.src.services
ShellRoot {
    property var notificationService: Notifications
    IpcHandler {
        target: "fixture"
        function state(): string {
            return JSON.stringify({
                latest: Notifications.latest?.summary ?? "",
                showing: Notifications.showing,
                burst: Notifications.burst,
                apps: Settings.ephemeralNotificationApps,
                kept: Notifications.list.map(n => n.summary)
            });
        }
        // As modules/Notice.qml's buttons.
        function left(): void {
            const n = Notifications.latest;
            if (n?.actions.some(a => a.identifier === "default"))
                Notifications.activate(n);
            else
                Notifications.focusOn(n);
            Notifications.dismissNotice(n);
        }
        function right(): void {
            const n = Notifications.latest;
            const answered = n?.urgency === 2;
            Notifications.dismissNotice(n);
            if (answered && Notifications.list.includes(n))
                n.dismiss();
        }
        function middle(): void {
            Notifications.dismissNotice(Notifications.latest);
        }
        function close(summary: string): void {
            Notifications.list.find(n => n.summary === summary)?.dismiss();
        }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="quickshell-notification-cap-") as folder:
        target = fixture_root(folder)
        (target / "src/services").mkdir(parents=True, exist_ok=True)
        # A ceiling of three, so the test need not send two hundred.
        service = (ROOT / "src/services/Notifications.qml").read_text()
        assert "property int keep: 200" in service
        service = service.replace("property int keep: 200", "property int keep: 3")
        (target / "src/services/Notifications.qml").write_text(service)
        for name in ("src/core/Settings.qml", "settings.default.json"):
            (target / name).write_text((ROOT / name).read_text())
        (target / "settings.json").write_text("{}\n")
        (target / "src/core/Theme.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var glyph: ({notif: "N"}) }\n')
        (target / "src/core/OpenPopup.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { function dismiss() {} }\n')
        (target / "shell.qml").write_text(SHELL)
        (target / "client.py").write_text(CLIENT)
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
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime),
                   XDG_STATE_HOME=str(target / "state"), XDG_CACHE_HOME=str(target / "cache"))
        for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            env.pop(key, None)
        return subprocess.run(["dbus-run-session", "--config-file", str(target / "bus.conf"), "--", "/usr/bin/python3",
                               str(target / "client.py"), str(target)], env=env, timeout=30).returncode


if __name__ == "__main__":
    raise SystemExit(main())

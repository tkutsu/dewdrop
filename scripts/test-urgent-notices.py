#!/usr/bin/env python3
"""Check urgent notice queuing and configurable ephemeral notification retention."""

import os
from pathlib import Path
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

    # Urgent stays, whatever timeout its sender gave it; arrivals queue.
    send("A", urgency=2, timeout=300)
    expect(latest="A", showing=True, burst=0)
    send("B")
    send("C")
    time.sleep(0.5)
    expect(latest="A", showing=True, burst=2)

    # A fleeting one behind it is let go, not counted.
    send("D", app="udiskie")
    state = expect(latest="A", burst=2)
    assert "D" not in state["kept"], state

    # A second urgent one queues too, and comes before the normal ones.
    send("E", urgency=2, actions=["default", "Open"])
    expect(latest="A", burst=3)

    # Right on an urgent one clears it from the centre too.
    ipc("right")
    state = expect(latest="E", showing=True, burst=2)
    assert "A" not in state["kept"], state

    # One withdrawn while waiting no longer counts.
    ipc("close", "C")
    expect(latest="E", burst=1)

    # Left runs its action, and the newest normal one gets its usual turn.
    ipc("left")
    state = expect(latest="B", showing=True, burst=0)
    assert "E" not in state["kept"], state
    expect(showing=False)

    # An urgent one arriving over a normal one takes over at no count.
    send("F")
    expect(latest="F", showing=True)
    send("G", urgency=2)
    expect(latest="G", showing=True, burst=0)
    ipc("middle")
    state = expect(showing=False)
    assert "G" in state["kept"], state

    # All existing app rules and both mail senders expire with their notices.
    for app in ("Herdr", "Email", "Gmail", "satty", "qBittorrent", "udiskie", "gMaIl"):
        summary = "Ephemeral " + app
        send(summary, app=app, timeout=300)
        expect(latest=summary, showing=True)
        state = expect(showing=False)
        assert summary not in state["kept"], state

    # Settings changes affect the next arrival without restarting the server.
    Path(target, "settings.json").write_text(json.dumps({"ephemeralNotificationApps": ["Custom Mail"]}))
    expect(apps=["Custom Mail"])
    send("Custom app", app="custom mail", timeout=300)
    expect(latest="Custom app", showing=True)
    state = expect(showing=False)
    assert "Custom app" not in state["kept"], state
    send("Removed app", app="Gmail", timeout=300)
    expect(latest="Removed app", showing=True)
    state = expect(showing=False)
    assert "Removed app" in state["kept"], state

    # Opening an ephemeral notification in the centre retains it.
    send("Keep in centre", app="Custom Mail", timeout=300)
    expect(latest="Keep in centre", showing=True)
    ipc("left")
    state = expect(showing=False)
    assert "Keep in centre" in state["kept"], state

    # An empty app list keeps normal notifications; sender hints and summary
    # rules still expire notifications meant only for the moment.
    Path(target, "settings.json").write_text(json.dumps({"ephemeralNotificationApps": []}))
    expect(apps=[])
    send("Unlisted app", timeout=300)
    expect(latest="Unlisted app", showing=True)
    state = expect(showing=False)
    assert "Unlisted app" in state["kept"], state
    for summary, transient in (("Transient hint", True), ("hyprwhspr finished", False), ("Claude Code finished", False)):
        send(summary, transient=transient, timeout=300)
        expect(latest=summary, showing=True)
        state = expect(showing=False)
        assert summary not in state["kept"], state

    passed = True
    print("PASS: urgent notices stay until answered and hand over to what waited behind them")
    print("PASS: ephemeral defaults, edited app lists, transient hints and centre retention")
finally:
    shell.terminate()
    output, _ = shell.communicate(timeout=3)
    if not passed:
        print(output)
'''


SHELL = r'''import Quickshell
import Quickshell.Io
import qs
import qs.services
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
    with tempfile.TemporaryDirectory(prefix="quickshell-urgent-notices-") as folder:
        target = Path(folder)
        (target / "services").mkdir()
        # Normal notices shortened so the test does not wait out six seconds.
        service = (ROOT / "services/Notifications.qml").read_text()
        service = service.replace("NotificationUrgency.Low ? 3000 : 6000", "NotificationUrgency.Low ? 300 : 600")
        (target / "services/Notifications.qml").write_text(service)
        for name in ("Settings.qml", "RightPillOrder.js", "settings.default.json"):
            (target / name).write_text((ROOT / name).read_text())
        (target / "settings.json").write_text("{}\n")
        (target / "Theme.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property var glyph: ({notif: "N"}) }\n')
        (target / "OpenPopup.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { function dismiss() {} }\n')
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

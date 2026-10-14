"""Copy current shell sources before each test applies its own substitutions."""

import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def copy_shell(target):
    """Include tracked and new files without copying ignored machine state."""
    target = Path(target)
    files = subprocess.check_output(
        ["git", "-C", str(ROOT), "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
    ).decode().split("\0")
    for name in files:
        source = ROOT / name
        if name and source.is_file():
            destination = target / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
    (target / "settings.json").write_text("{}\n")
    offscreen_ink(target)


def offscreen_ink(target):
    """Give Ink's meter a plain window: the offscreen platform has no layer shell.

    Never writes through a link: a fixture that links the checkout's services/
    gets a real directory of links instead, and Ink.qml becomes a real file.
    """
    services = Path(target) / "services"
    if services.is_symlink():
        checkout = services.resolve()
        services.unlink()
        services.mkdir()
        for item in checkout.iterdir():
            (services / item.name).symlink_to(item)
    path = services / "Ink.qml"
    if not path.exists():
        return
    lines = path.read_text().replace("    PanelWindow {", "    FloatingWindow {", 1).splitlines()
    path.unlink()
    shell_only = ("anchors.top:", "anchors.left:", "exclusionMode:", "mask: Region", "WlrLayershell.")
    path.write_text("\n".join(line for line in lines if not line.strip().startswith(shell_only)) + "\n")


def shell_env(target, **overrides):
    """Keep display connections and all writable XDG paths inside the fixture."""
    target = Path(target)
    runtime = target / "runtime"
    runtime.mkdir(mode=0o700, exist_ok=True)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
               XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(target / "config"),
               XDG_STATE_HOME=str(target / "state"), XDG_DATA_HOME=str(target / "data"),
               XDG_CACHE_HOME=str(target / "cache"))
    for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS"):
        env.pop(key, None)
    env.update(overrides)
    return env

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

#!/usr/bin/env python3
"""Type Greek tonos through the compositor into an isolated task editor."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

spec = importlib.util.spec_from_file_location('task_harness', Path(__file__).with_name('test-tasks.py'))
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)

CASE = r'''
                Tasks.lists = [{id: "home", title: "Home"}];
                Tasks.tasks = [{id: "a", listId: "home", title: "Fixture", parent: "", position: "10", notes: ""}];
                wait(100);
                popup.beginEdit(Tasks.tasks[0]);
                wait(100);
                const editor = popup.keyInput;
                editor.selectAll();
                keyRelay.forceActiveFocus();
                wait(150);
                check(keyRelay.activeFocus, "bar relay has native keyboard focus");
                pointerMotion.command = ["ydotool", "key", "39:1", "39:0", "30:1", "30:0"];
                pointerMotion.running = true;
                tryCompare(pointerMotion, "running", false, 3000);
                check(pointerMotion.exitCode === 0, "native key injection succeeded");
                wait(200);
                check(popup.draft === "ά", "native dead tonos then alpha composes accented Greek through bar relay; received " + JSON.stringify(popup.draft));
                popup.cancelEdit();
'''
harness.SHELL = harness.SHELL.replace('Process { id: pointerMotion }', 'Process { id: pointerMotion; property int exitCode: -1; onExited: (code, status) => exitCode = code }')
start = harness.SHELL.index('                Tasks.lists =')
end = harness.SHELL.index('                console.log("DONE: tasks");', start)
harness.SHELL = harness.SHELL[:start] + CASE + harness.SHELL[end:]


def main():
    devices = json.loads(subprocess.check_output(['hyprctl', 'devices', '-j'], text=True))
    keyboard = next(k for k in devices['keyboards'] if k['name'] == 'ydotoold-virtual-device')
    greek = keyboard['layout'].split(',').index('gr')
    previous = keyboard['active_layout_index']
    try:
        subprocess.run(['hyprctl', 'switchxkblayout', keyboard['name'], str(greek)], check=True, capture_output=True)
        sys.argv.append('--live')
        return harness.main()
    finally:
        subprocess.run(['hyprctl', 'switchxkblayout', keyboard['name'], str(previous)], check=True, capture_output=True)


if __name__ == '__main__':
    raise SystemExit(main())

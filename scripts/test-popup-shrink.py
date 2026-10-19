#!/usr/bin/env python3
"""Exercise the bottom border's gel deformation after any popup height change."""

import argparse
import os
import selectors
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

from test_support import copy_shell, shell_env


QML = '''import QtQuick
import QtTest
import Quickshell
import qs
import qs.components
ShellRoot {
    FloatingWindow {
        visible: true
        implicitWidth: 800; implicitHeight: 800
        Item { id: anchor; width: 20; height: 20 }
        Popup {
            id: popup
            anchorItem: anchor; visible: true; probes: false
            Item {
                id: row; implicitWidth: 400; implicitHeight: 400
                Column {
                    spacing: 12
                    Text { text: "Notifications"; color: "#222"; font.pixelSize: 16 }
                    Repeater {
                        model: row.implicitHeight > 120 ? 6 : 1
                        delegate: Text {
                            required property int index
                            text: "Notification " + (index + 1); color: "#666"; font.pixelSize: 14
                        }
                    }
                }
            }
        }
        TestCase {
            id: test; when: false
            function check(ok, why) { if (!ok) throw Error(why); }
            function fill(item) {
                if (item.showFill === 1 && item.sag !== undefined && item.visible) return item;
                for (const child of item.children || []) {
                    const found = fill(child);
                    if (found) return found;
                }
                return null;
            }
            function run() {
                check(popup.animateContents, "the popup has finished opening");
                const surface = popup.height, width = popup.width;
                const top = popup.chromeItem.y;
                const position = row.mapToItem(popup.contentItem, 0, 0);
                const target = 120 + popup.vPadding + popup.bottomPadding;
                popup.chromeItem.frost = "white";
                wait(Theme.revealMs + 40);
                if (RECORD_PREVIEW) {
                    popup.chromeItem.parent.grabToImage(result => result.saveToFile(Quickshell.shellPath("frame-0.png")));
                    wait(40);
                }
                row.implicitHeight = 120;
                check(popup.chromeItem.height > target + 200, "shrink starts from the previous height");
                let maximumSag = 0, minimumSag = 0, bowed = false, rebounded = false;
                for (let i = 0; i < 65; i++) {
                    wait(16);
                    if (RECORD_PREVIEW && i % 2 === 0) {
                        const file = "frame-" + (i / 2 + 1) + ".png";
                        popup.chromeItem.parent.grabToImage(result => result.saveToFile(Quickshell.shellPath(file)));
                    }
                    const shape = fill(popup.chromeItem);
                    if (Math.abs(popup.chromeItem.height - target) > 0.05)
                        check(popup.chromeItem.sag === 0 && !shape,
                            "the border stays rigid until it reaches its destination");
                    if (shape) {
                        maximumSag = Math.max(maximumSag, shape.sag);
                        minimumSag = Math.min(minimumSag, shape.sag);
                        if (!bowed && shape.sag > 3) {
                            bowed = true;
                            shape.grabToImage(result => result.saveToFile(Quickshell.shellPath("bowed.png")));
                        }
                        if (!rebounded && shape.sag < -0.2) {
                            rebounded = true;
                            shape.grabToImage(result => result.saveToFile(Quickshell.shellPath("rebounded.png")));
                        }
                    }
                    check(popup.height === surface && popup.width === width,
                        "resizing leaves the compositor surface fixed");
                    const p = row.mapToItem(popup.contentItem, 0, 0);
                    check(popup.chromeItem.y === top && Math.abs(p.y - position.y) < 0.01
                        && Math.abs(p.x - position.x) < 0.01,
                        "the top edge and content stay anchored during shrink");
                    check(popup.growX === 1 && popup.growY === 1,
                        "shrink does not restart the opening scale");
                }
                console.log("bottom border sag: " + maximumSag.toFixed(2) + " / " + minimumSag.toFixed(2) + " px");
                wait(40);
                check(maximumSag > 1 && maximumSag < 7 && minimumSag < -0.05,
                    "the bottom border bows and rebounds, rather than staying rigid");
                check(Math.abs(minimumSag) < maximumSag / 4,
                    "the recoil in the other direction is smaller than the initial flex");
                check(Math.abs(popup.chromeItem.height - target) < 0.05, "the spring settles at the new height");
                row.implicitHeight = 400;
                wait(20);
                check(popup.chromeItem.height < popup.chromeHeight - 100,
                    "every popup eases into its expanded height");
                let expansionSag = 0, expansionRecoil = 0, expanded = false;
                for (let i = 0; i < 65; i++) {
                    wait(16);
                    if (popup.chromeItem.height !== popup.chromeHeight)
                        check(popup.chromeItem.sag === 0, "expansion stays rigid until landing");
                    const sag = popup.chromeItem.sag;
                    check(expansionSag > 0 || sag >= 0, "expansion bows down first");
                    expansionSag = Math.max(expansionSag, sag);
                    expansionRecoil = Math.min(expansionRecoil, sag);
                    if (!expanded && sag > 3) {
                        expanded = true;
                        fill(popup.chromeItem).grabToImage(result => result.saveToFile(Quickshell.shellPath("expanded.png")));
                    }
                    check(popup.height === surface, "expansion reuses the surface's reserved height");
                }
                check(expansionSag > 1 && expansionSag <= 5 && expansionRecoil < -0.05
                    && Math.abs(expansionRecoil) < expansionSag / 4,
                    "expansion bows down and has one smaller opposite recoil");
                row.implicitHeight = 250;
                wait(80);
                row.implicitHeight = 120;
                wait(1100);
                check(Math.abs(popup.chromeItem.height - target) < 0.05,
                    "a second removal retargets and settles");
                Settings.user = Object.assign({}, Settings.user, {reduceMotion: true});
                row.implicitHeight = 400;
                wait(20);
                row.implicitHeight = 120;
                wait(20);
                check(popup.chromeItem.height === target, "Reduce Motion skips the shrink spring");
                check(!popup.chromeItem.shaped && popup.chromeItem.sag === 0,
                    "Reduce Motion keeps the bottom border straight");
                Settings.user = Object.assign({}, Settings.user, {reduceMotion: false});
                row.implicitHeight = 250;
                wait(80);
                popup.requestedVisible = false;
                const closingHeight = popup.chromeItem.height;
                row.implicitHeight = 400;
                wait(400);
                check(popup.chromeItem.height === closingHeight && popup.height === surface,
                    "a closing popup holds its size even when its content changes");
                check(!popup.chromeItem.shaped && popup.chromeItem.sag === 0 && popup.revealProgress === 0,
                    "a closing popup fades without flexing");
                console.log("PASS: popup shrink rebound");
            }
        }
        Timer { interval: 1000; running: true; onTriggered: {
            try { test.run(); } catch (e) { console.log("FAIL: " + e + "\\n" + e.stack); }
            Qt.quit();
        } }
    }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", type=Path, help="Save the rendered animation preview here")
    parser.add_argument("--hot-reload", action="store_true", help="Start with the cached rigid shader, then reload")
    options = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="qs-popup-shrink-") as folder:
        target = Path(folder)
        copy_shell(target)
        qml = QML.replace("RECORD_PREVIEW", "true" if options.preview else "false")
        try:
            result = run_shell(target, qml, options.hot_reload)
        except subprocess.TimeoutExpired as error:
            print((error.stdout or b"").decode() + (error.stderr or b"").decode())
            return 1
        output = result.stdout + result.stderr
        print("\n".join(line for line in output.splitlines()
                        if "qml:" in line or "ERROR" in line))
        errors = ("FAIL:", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign",
                  "Cannot assign", "Failed to load configuration")
        if (result.returncode != 0 or "PASS: popup shrink rebound" not in output
                or any(error in output for error in errors)):
            print(output)
            return 1
        for name, direction in (("bowed", 1), ("rebounded", -1), ("expanded", 1)):
            path = target / f"{name}.png"
            if not path.exists():
                print(f"FAIL: missing rendered {name} border")
                return 1
            frame = Image.open(path).convert("RGBA")
            center = bottom_edge(frame, frame.width // 2)
            side = bottom_edge(frame, frame.width // 10)
            bend = center - side
            print(f"{name} border center versus side: {bend:.2f} px")
            if bend * direction < (1 if direction > 0 else 0.04):
                print(f"FAIL: rendered {name} border remains rigid")
                return 1
        print("PASS: rendered bottom border bows and rebounds")
        if options.preview:
            options.preview.mkdir(parents=True, exist_ok=True)
            paths = sorted(target.glob("frame-*.png"), key=lambda path: int(path.stem.split("-")[1]))
            frames = [Image.open(path).convert("RGBA") for path in paths]
            height = max(frame.getbbox()[3] for frame in frames)
            pictures = []
            for frame in frames:
                picture = Image.new("RGB", (frame.width, height), "#202023")
                picture.paste(frame, mask=frame.getchannel("A"))
                pictures.append(picture)
            pictures[0].save(options.preview / "shrink.gif", save_all=True, append_images=pictures[1:],
                             duration=[500] + [32] * (len(pictures) - 2) + [1000], loop=0, disposal=2)
            print(f"Preview: {options.preview / 'shrink.gif'}")
        return 0


def run_shell(target, qml, hot_reload):
    """Exercise both a fresh renderer and the live shell's shader cache across reloads."""
    command = ["qs", "-p", str(target), "--no-color"]
    env = shell_env(target, QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl",
                    LIBGL_ALWAYS_SOFTWARE="1", QSG_RENDER_LOOP="basic")
    shell = target / "shell.qml"
    if not hot_reload:
        shell.write_text(qml)
        return subprocess.run(command, env=env, capture_output=True, text=True, timeout=10)

    shader = target / "shaders/drop.frag.qsb"
    current_shader = shader.read_bytes()
    source = target / "shaders/drop.frag"
    source.write_text(source.read_text().replace(
        "q0.y -= sag * max(1.0 - u * u, 0.0) * t;", "q0.y -= 0.0;"))
    subprocess.run(["/usr/lib/qt6/bin/qsb", "--qt6", "-o", str(shader), str(source)], check=True)
    drop = target / "components/Drop.qml"
    current_drop = drop.read_text()
    drop.write_text(current_drop.replace("?revision=bottom-flex", ""))
    shell.write_text('''import QtQuick
import Quickshell
import qs.components
ShellRoot {
    FloatingWindow {
        visible: true; implicitWidth: 200; implicitHeight: 200
        Drop {
            anchors.fill: undefined; width: 100; height: 120
            box: Qt.vector4d(0, 0, 100, 100); radius: 10; sag: 5; color: "white"; showFill: 1
        }
        Timer { interval: 300; running: true; onTriggered: console.log("SHADER_WARMED") }
    }
}
''')
    with subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as process:
        output = b""
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while b"SHADER_WARMED" not in output:
                if not selector.select(timeout=5):
                    process.kill()
                    raise subprocess.TimeoutExpired(command, 5, output=output)
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    return subprocess.CompletedProcess(command, process.wait(), output.decode(), "")
                output += chunk
        shader.write_bytes(current_shader)
        drop.write_text(current_drop)
        shell.write_text(qml)
        try:
            remaining, _ = process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
            raise
        return subprocess.CompletedProcess(command, process.returncode, (output + remaining).decode(), "")


def bottom_edge(frame, x):
    """Locate the half-alpha contour, retaining subpixel motion in the rebound."""
    alpha = [frame.getpixel((x, y))[3] / 255 for y in range(frame.height)]
    y = max(i for i, value in enumerate(alpha) if value >= 0.5)
    return y + (alpha[y] - 0.5) / (alpha[y] - alpha[y + 1])


if __name__ == "__main__":
    raise SystemExit(main())

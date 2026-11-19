#!/usr/bin/env python3
"""Drive the polkit password panel offscreen with a stand-in request.

Typing and Return answer it, a refusal empties the field and keeps the keys,
Escape cancels, and a request several users could answer offers the choice.
"""

from pathlib import Path
import re
import subprocess
import tempfile

from test_support import copy_shell, shell_env

ROOT = Path(__file__).resolve().parents[1]

SHELL = '''import QtQuick
import QtTest
import Quickshell
import qs.src.modules

ShellRoot {
    QtObject {
        id: flow

        readonly property var me: ({ id: 1000, string: Quickshell.env("USER"), displayName: "", isGroup: false })
        readonly property var other: ({ id: 1001, string: "ada", displayName: "Ada Lovelace", isGroup: false })
        property string message: "Authentication is required to run `/usr/bin/true' as the super user"
        property var identities: [me]
        property var selectedIdentity: me
        property bool isResponseRequired: true
        property string inputPrompt: "Password: "
        property bool responseVisible: false
        property string supplementaryMessage: ""
        property bool supplementaryIsError: false
        property string answer: ""
        property bool cancelled: false

        signal authenticationFailed

        function submit(value) { answer = value; isResponseRequired = false; }
        function cancelAuthenticationRequest() { cancelled = true; }
    }

    AuthDialog {
        id: dialog
        flow: flow

        TestCase {
            id: test
            when: false

            function check(ok, message) { if (!ok) throw Error(message); }

            function texts(item, out) {
                if (item.text !== undefined && item.visible && typeof item.text === "string")
                    out.push(item.text);
                for (const child of item.children)
                    texts(child, out);
                return out;
            }

            function focused() { return dialog.contentItem.Window.activeFocusItem; }

            function run() {
                dialog.contentItem.Window.window.requestActivate();
                wait(200);
                const shown = texts(dialog.contentItem, []);
                check(shown.includes("Authentication is required to run “/⁠usr/⁠bin/⁠true” as the super user."), "title is polkit's message as a sentence: " + shown);
                check(shown.includes("Enter your password to allow this."), "names the user's own password: " + shown);
                check(shown.includes("Password"), "the prompt is the placeholder: " + shown);
                const field = focused();
                check(field && field.echoMode === TextInput.Password, "the field has the keys and hides them");

                const caps = dialog.capsLock;
                keyClick(Qt.Key_CapsLock);
                check(dialog.capsLock === !caps, "the Caps Lock key flips the arrow");
                keyClick(Qt.Key_CapsLock);

                keyClick(Qt.Key_S); keyClick(Qt.Key_E); keyClick(Qt.Key_C);
                check(!dialog.capsLock, "a lower-case letter without Shift means Caps Lock is off");
                check(field.color.a === 0 && field.children.some(c => c.cell > 0 && c.count === 3), "the field's own characters stay unseen under the drawn ones");
                keyClick(Qt.Key_Return);
                check(flow.answer === "sec", "Return submits what was typed: " + flow.answer);
                check(dialog.checking, "waits on the answer");

                flow.authenticationFailed();
                flow.isResponseRequired = true;
                wait(50);
                check(field.text === "" && dialog.refused, "a refusal empties the field");
                check(focused() === field, "and keeps the keys");
                keyClick(Qt.Key_X);
                check(!dialog.refused, "typing again clears the refusal");

                keyClick(Qt.Key_Escape);
                check(flow.cancelled, "Escape cancels");

                flow.identities = [flow.me, flow.other];
                wait(50);
                check(texts(dialog.contentItem, []).includes("Enter an administrator’s password."), "several users offer the choice");
                flow.identities = [flow.other];
                flow.selectedIdentity = flow.other;
                wait(50);
                check(texts(dialog.contentItem, []).includes("Enter the password for Ada Lovelace to allow this."), "another user's password is named");
                flow.identities = [flow.me];
                flow.selectedIdentity = flow.me;
                flow.cancelled = false;
                field.text = "";
                console.log("PASS: auth dialog");
            }
        }

        Timer {
            interval: 500
            running: true
            onTriggered: {
                try { test.run(); } catch (e) { console.log("FAIL: " + e); }
                Qt.quit();
            }
        }
    }
}
'''


def offscreen(text):
    """A plain window in place of the layer-shell surface the platform lacks."""
    text = text.replace("PanelWindow {\n    id: root\n", "FloatingWindow {\n    id: root\n    implicitWidth: 480\n    implicitHeight: 400\n", 1)
    text = re.sub(r"\n    anchors \{.*?\n    \}\n", "\n", text, count=1, flags=re.S)
    text = re.sub(r"\n    mask: Region \{.*?\n    \}\n", "\n", text, count=1, flags=re.S)
    return "\n".join(line for line in text.splitlines()
                     if not line.strip().startswith(("WlrLayershell.", "exclusionMode:"))) + "\n"


def main():
    with tempfile.TemporaryDirectory(prefix="qs-auth-dialog-") as folder:
        target = Path(folder)
        copy_shell(target)
        dialog = target / "src/modules/AuthDialog.qml"
        dialog.write_text(offscreen(dialog.read_text()))
        (target / "shell.qml").write_text(SHELL)
        env = shell_env(target)
        # A shell that fails to load stays up, so it is stopped, not waited for.
        process = subprocess.Popen(["qs", "-p", str(target), "--no-color"], env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            output, _ = process.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            process.terminate()
            output, _ = process.communicate()
        print(output, end="")
        return 0 if "PASS: auth dialog" in output and "FAIL:" not in output else 1


if __name__ == "__main__":
    raise SystemExit(main())

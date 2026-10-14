import QtQuick
import qs

// The compositor sends composed text to its focused field, independently of
// Keys.forwardTo. Keep that field on the bar and insert commits in the editor.
TextEdit {
    id: root

    property Item input: null
    property var keyHandler: event => OpenPopup.key(event)
    focus: true
    readOnly: !root.input
    visible: true
    width: 0
    height: 0
    Accessible.ignored: true
    textFormat: TextEdit.PlainText
    Keys.forwardTo: root.input ? [root.input] : []
    Keys.onPressed: event => event.accepted = root.keyHandler(event)

    onTextChanged: {
        if (!text) return;
        const committed = text;
        clear();
        if (!root.input) return;
        root.input.remove(root.input.selectionStart, root.input.selectionEnd);
        const at = root.input.cursorPosition;
        root.input.insert(at, committed);
        root.input.cursorPosition = at + committed.length;
    }
}

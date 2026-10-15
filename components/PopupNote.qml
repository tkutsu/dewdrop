import QtQuick
import qs

// A line in place of a list, or about it: nothing there ("No devices"),
// something on its way ("Looking for networks…"), something wrong. Sentence
// case, and "…" for what is under way. `warn` is for the line that is the
// trouble rather than news of it.
PopupText {
    property bool warn: false

    leftPadding: Theme.popupInset
    rightPadding: Theme.popupInset
    wrapMode: Text.Wrap
    color: warn ? Theme.warn : Theme.label2
}

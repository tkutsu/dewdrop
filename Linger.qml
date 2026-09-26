import QtQuick
import qs

// The gap between a menu being unwanted and its window going away.
//
// A menu folds itself shut rather than vanishing, so a loader bound straight to
// `shown` would tear the surface down before a frame of that was drawn. This is
// `shown` held open for the length of the animation: bind a LazyLoader to
// `active` and the window outlives the intent by exactly one reveal.
Timer {
    id: root

    required property bool shown

    // Wanted, or still on the way out.
    //
    // Deliberately a property the handler sets rather than a binding on
    // `shown || running`: that binding and the handler below are both driven by
    // the same `shownChanged`, and which of the two Qt runs first is not
    // something to build a window's lifetime on. Set outright, there is no
    // order to get wrong.
    property bool active: false

    // How long the surface outlives the intent. A reveal's length, because a
    // menu folding shut is its reveal run backwards — but not every way out is
    // a fold: the launcher leaves on a choice with a longer animation of its
    // own and says so here. See modules/LauncherMenu.qml.
    property int hold: Theme.revealMs

    interval: root.hold

    onShownChanged: {
        if (root.shown) {
            // Reopened inside its own closing animation: the window is still
            // there, so it animates back open rather than being rebuilt.
            root.stop();
            root.active = true;
        } else {
            root.restart();
        }
    }

    onTriggered: root.active = false
}

pragma Singleton

import Quickshell

// How many of the bar's popups have the pointer on them — none or one, in
// practice. A popup is a window of its own, so to the bar a pointer that has
// gone down into one looks the same as a pointer that has left; this is the
// difference. Kept by components/Popup.qml.
Singleton {
    property int hovered: 0
}

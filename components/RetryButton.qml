import QtQuick
import qs

// Retry the service's read check immediately, keeping the target while busy:
// faint until it is back, with the same label.
PopupButton {
    required property var service

    visible: service.retryable
    live: !service.loading
    framed: true
    glyph: Theme.glyph.refresh
    label: "Retry"
    onTapped: service.retryNow()
}

import QtQuick
import qs

// Retry the service's read check immediately, keeping the target while busy.
PopupButton {
    required property var service

    visible: service.retryable
    live: !service.loading
    framed: true
    glyph: Theme.glyph.refresh
    label: service.loading ? "retrying…" : "retry"
    onTapped: service.retryNow()
}

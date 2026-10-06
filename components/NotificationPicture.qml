import QtQuick
import qs.services

// A notification's picture (its image hint) and where it belongs. Senders put
// two kinds of thing there: a mark of their own — a logo, a contact's avatar,
// whatever `notify-send -i` was given — and content, such as a screenshot or
// a photo. A mark goes where the app icon goes; content gets a preview of
// its own under the text.
//
// Told apart by what the picture is, not by who sent it: a theme icon, a file
// from an icon folder or a vector is a mark, and so is a small, roughly
// square picture. Anything else is content.
Item {
    id: root

    property var notification: null

    readonly property string source: Notifications.url(root.notification?.image)

    // A mark by its name alone, with nothing to load.
    readonly property bool named: root.source.startsWith("image://icon/") || /\/(?:icons|pixmaps)\/|\.svgz?$/i.test(root.source)

    readonly property bool isIcon: root.source !== "" && (root.named || probe.status === Image.Ready && root.small)
    readonly property bool isPreview: !root.named && probe.status === Image.Ready && !root.small

    // Never above iconMax on a side, and neither side more than a quarter
    // longer than the other.
    readonly property int iconMax: 256
    readonly property bool small: {
        const w = probe.implicitWidth, h = probe.implicitHeight;
        return w > 0 && h > 0 && Math.max(w, h) <= root.iconMax && Math.max(w, h) / Math.min(w, h) <= 1.25;
    }

    visible: false

    // Loaded no larger than a pixel past the limit: a raster is never scaled
    // up, so one inside it reports its own size, and one past it comes back
    // past it in its own shape, without decoding a whole screenshot to learn so.
    // Raw pixels sent with the notification come back at their full size,
    // which answers the same question.
    Image {
        id: probe
        source: root.named ? "" : root.source
        sourceSize: Qt.size(root.iconMax + 1, root.iconMax + 1)
        asynchronous: true
    }
}

import QtQuick
import "../lib/FileUrl.js" as FileUrl

// The wallpaper framed the way Backdrop.qml frames it: zoomed by `zoom` and
// its crop at (`panX`, `panY`), each from 0 at one edge of the spare room to
// 1 at the other. The curtain and the lock screen both draw it, so the one
// can hand over to the other without a seam.
//
// Decoded once at `decodeZoom`, the largest the framing reaches, and scaled
// down from there: a size bound to a zoom in motion would decode the picture
// again every frame.
Rectangle {
    id: root

    property string path: ""
    property color swatch: "black"
    property real zoom: 1
    property real decodeZoom: 1
    property real panX: 0.5
    property real panY: 0.5
    readonly property bool ready: !root.path || image.status === Image.Ready || image.status === Image.Error

    color: root.swatch

    Image {
        id: image

        visible: root.path !== ""
        width: root.width * root.decodeZoom
        height: root.height * root.decodeZoom
        x: (root.width - width) / 2 + (0.5 - root.panX) * root.width * (root.zoom - 1)
        y: (root.height - height) / 2 + (0.5 - root.panY) * root.height * (root.zoom - 1)
        scale: root.zoom / root.decodeZoom
        source: FileUrl.fromPath(root.path)
        sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        mipmap: true
    }
}

pragma Singleton

import QtQuick
import Quickshell

// Remembers where the ink of a piece of text actually landed once it was
// drawn, so a glyph is measured once and every copy of it on the bar sits on
// the same rows. The sibling of IconInk, for text: the font's own metrics say
// where a glyph's outline is, and the rasteriser then snaps its strokes to
// whole rows, which at bar sizes is a pixel or two away from the outline. The
// only way to know where the pixels went is to look (components/InkProbe.qml).
//
// Keyed by everything that changes the rendering — family, weight, size and
// the text itself — and holding the ink's first and last row and column,
// relative to the Text item it was measured on.
Singleton {
    id: root

    property var known: ({})

    // Bumped on every write so that a binding reading through boundsOf()
    // re-runs; a plain object's properties do not notify on their own.
    property int revision: 0

    function keyOf(family, weight, size, text) {
        return family + "|" + weight + "|" + size + "|" + text;
    }

    function boundsOf(key) {
        root.revision;
        return root.known[key] ?? null;
    }

    function remember(key, top, bottom, left, right) {
        root.known[key] = {
            top: top,
            bottom: bottom,
            left: left,
            right: right
        };
        root.revision++;
    }
}

import QtQuick
import qs

// Scale the outermost icon in a module; its text and nested artwork keep their size.
Scale {
    required property Item icon
    readonly property Item module: {
        for (let item = icon.parent; item; item = item.parent) {
            if (item instanceof Glyph || item instanceof AppIcon || item instanceof BadgedGlyph)
                return null;
            if (item instanceof BarItem)
                return item;
        }
        return null;
    }
    origin.x: icon.width / 2
    origin.y: icon.height / 2
    xScale: module?.appearanceScale ?? 1
    yScale: xScale
}

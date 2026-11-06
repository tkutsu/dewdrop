import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// Opens the downloads folder. Out of the drawer while something in there has
// not been opened yet.
BarItem {
    quiet: Downloads.unopened.length === 0
    name: "Downloads"
    tooltip: {
        const files = Downloads.unopened;
        return files.length === 0 ? "Downloads" : files.length === 1 ? files[0].name : `${files.length} new downloads`;
    }

    Glyph {
        Layout.fillHeight: true
        text: Theme.glyph.downloads
        fontSize: Theme.glyphSizeLarge
    }

    actions: ({
            [Qt.LeftButton]: () => Downloads.open()
        })
}

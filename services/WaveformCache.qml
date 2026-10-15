pragma Singleton

import Quickshell

// The last decoded song survives the music popup being unloaded.
Singleton {
    property string loaded: ""
    property var samples: []
    property var beats: []
}

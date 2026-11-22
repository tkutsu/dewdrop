pragma Singleton

import qs.src.bar
import "../lib/RightPillOrder.js" as Order

// The centre pill's order. Every module retains its central slot while shown
// in the right pill.
PillOrder {
    file: "centre-pill.json"
    defaults: ["privacy", "datetime", "weather", ...Order.normalise([]).filter(key => !["privacy", "datetime", "weather"].includes(key))]
    // A saved order from before Privacy was a module puts it at the left
    // end, where its icon used to sit.
    front: ["privacy"]
}

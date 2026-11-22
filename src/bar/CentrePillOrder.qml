pragma Singleton

import qs.src.bar
import "../lib/RightPillOrder.js" as Order

// The centre pill's order. Every module retains its central slot while shown
// in the right pill.
PillOrder {
    file: "centre-pill.json"
    defaults: ["datetime", "weather", ...Order.normalise([]).filter(key => !["datetime", "weather"].includes(key))]
}

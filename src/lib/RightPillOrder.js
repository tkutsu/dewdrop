// Grouped by kind (kindOf) after the volume, which leads.
const defaults = ["audio", "email", "tasks", "updater", "feeds", "downloads", "bell",
    "satty", "wallpaper", "tray", "settings",
    "idle", "night", "language",
    "sys", "drives", "bluetooth", "network", "weather", "datetime", "countdown"];

// What a module is for: things waiting for you, tools you open, switches you
// flip, and readouts. The open drawer draws a hairline where one kind gives
// way to the next (Pill.kindOf).
const kinds = {
    email: "inbox", tasks: "inbox", feeds: "inbox", updater: "inbox", downloads: "inbox", bell: "inbox",
    satty: "tool", wallpaper: "tool", tray: "tool", settings: "tool",
    idle: "toggle", night: "toggle", audio: "toggle", language: "toggle",
    sys: "status", drives: "status", bluetooth: "status", network: "status",
    weather: "status", datetime: "status", countdown: "status"
};

function kindOf(key) {
    return kinds[key] ?? "";
}

// Keep saved positions while accepting modules added since the last drop.
function normalise(order, supported = defaults) {
    const keys = [];
    for (let key of Array.isArray(order) ? order : []) {
        if (key === "date" || key === "time")
            key = "datetime";
        if (supported.includes(key) && !keys.includes(key))
            keys.push(key);
    }
    for (const key of supported)
        if (!keys.includes(key))
            keys.push(key);
    return keys;
}

// Refill only visible slots, leaving every hidden module in its saved position.
function move(order, key, beforeKey, visibleKeys, supported = defaults) {
    const keys = normalise(order, supported);
    const visible = keys.filter(k => visibleKeys.includes(k));
    if (!visible.includes(key) || beforeKey === key
        || (beforeKey !== null && !visible.includes(beforeKey)))
        return keys;
    visible.splice(visible.indexOf(key), 1);
    visible.splice(beforeKey === null ? visible.length : visible.indexOf(beforeKey), 0, key);
    let index = 0;
    return keys.map(k => visibleKeys.includes(k) ? visible[index++] : k);
}

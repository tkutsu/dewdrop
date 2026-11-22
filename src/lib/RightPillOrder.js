// The modules the pills order. The bell and timers are not among them: they
// are fused to the centre pill's right end (Bar.qml).
const defaults = ["audio", "email", "tasks", "updater", "feeds", "downloads", "satty", "idle",
    "wallpaper", "night", "sys", "settings", "drives", "bluetooth", "network", "tray", "language", "weather", "datetime", "privacy"];

// Keep saved positions while accepting modules added since the last drop:
// at the end, or at the front for those listed in `front`.
function normalise(order, supported = defaults, front = []) {
    const keys = [];
    for (let key of Array.isArray(order) ? order : []) {
        if (key === "date" || key === "time")
            key = "datetime";
        if (supported.includes(key) && !keys.includes(key))
            keys.push(key);
    }
    const added = supported.filter(key => !keys.includes(key));
    return [...added.filter(key => front.includes(key)), ...keys, ...added.filter(key => !front.includes(key))];
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

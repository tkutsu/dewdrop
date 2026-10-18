const defaults = ["audio", "email", "tasks", "updater", "feeds", "bell", "satty", "idle",
    "wallpaper", "night", "sys", "settings", "drives", "bluetooth", "network", "tray", "language", "weather", "date", "time"];

// Keep saved positions while accepting modules added since the last drop.
function normalise(order, supported = defaults) {
    const keys = [];
    for (const key of Array.isArray(order) ? order : [])
        if (supported.includes(key) && !keys.includes(key))
            keys.push(key);
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

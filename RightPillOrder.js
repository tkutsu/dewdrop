const defaults = ["audio", "email", "tasks", "updater", "bell", "weather", "satty", "idle",
    "wallpaper", "night", "sys", "bluetooth", "network", "tray", "language"];

// Keep saved positions while accepting modules added since the last drop.
function normalise(order) {
    const keys = [];
    for (const key of Array.isArray(order) ? order : [])
        if (defaults.includes(key) && !keys.includes(key))
            keys.push(key);
    for (const key of defaults)
        if (!keys.includes(key))
            keys.push(key);
    return keys;
}

// Refill only visible slots, leaving every hidden module in its saved position.
function move(order, key, beforeKey, visibleKeys) {
    const keys = normalise(order);
    const visible = keys.filter(k => visibleKeys.includes(k));
    if (!visible.includes(key) || beforeKey === key
        || (beforeKey !== null && !visible.includes(beforeKey)))
        return keys;
    visible.splice(visible.indexOf(key), 1);
    visible.splice(beforeKey === null ? visible.length : visible.indexOf(beforeKey), 0, key);
    let index = 0;
    return keys.map(k => visibleKeys.includes(k) ? visible[index++] : k);
}

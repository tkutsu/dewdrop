// Which pill each ordered module sits in, and in what order: one list per
// pill, every module in exactly one of them. The bell and timers are not
// among them: they are fused to the centre pill's right end (Bar.qml).

// Date & Time, Weather and Privacy never leave the centre pill.
const fixedCentre = ["privacy", "datetime", "weather"];
const defaults = {
    centre: fixedCentre,
    right: ["audio", "email", "tasks", "updater", "feeds", "downloads", "satty", "idle",
        "wallpaper", "night", "sys", "settings", "drives", "bluetooth", "network", "tray", "language"],
};
const keys = [...defaults.centre, ...defaults.right];

function unique(list) {
    const out = [];
    for (const key of Array.isArray(list) ? list : [])
        if (keys.includes(key) && !out.includes(key))
            out.push(key);
    return out;
}

// The saved places, with fixed modules back in the centre and modules added
// since at the end of their default pill.
function normalise(saved) {
    const centre = unique(saved?.centre);
    const right = unique(saved?.right).filter(key => !centre.includes(key) && !fixedCentre.includes(key));
    const missing = pill => defaults[pill].filter(key => !centre.includes(key) && !right.includes(key));
    return { centre: [...centre, ...missing("centre")], right: [...right, ...missing("right")] };
}

// Drop `key` before `beforeKey` (null: at the end) among the visible modules
// of `pill`, from either pill. Hidden modules keep their slots.
function move(places, key, pill, beforeKey, visibleKeys) {
    const from = places.centre.includes(key) ? "centre" : "right";
    if (from !== pill && fixedCentre.includes(key))
        return places;
    const list = from === pill ? places[pill] : [...places[pill], key];
    const visible = list.filter(k => visibleKeys.includes(k));
    if (!visible.includes(key) || beforeKey === key || (beforeKey !== null && !visible.includes(beforeKey)))
        return places;
    visible.splice(visible.indexOf(key), 1);
    visible.splice(beforeKey === null ? visible.length : visible.indexOf(beforeKey), 0, key);
    let index = 0;
    const next = Object.assign({}, places, { [pill]: list.map(k => visibleKeys.includes(k) ? visible[index++] : k) });
    if (from !== pill)
        next[from] = places[from].filter(k => k !== key);
    return next;
}

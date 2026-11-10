.pragma library

// Collect controls under visible, enabled branches; callers choose eligibility and order.
function collect(item, eligible) {
    const found = [];
    function walk(parent) {
        for (const child of parent.children) {
            if (!child.visible || !child.enabled || child.opacity === 0)
                continue;
            if (eligible(child))
                found.push(child);
            walk(child);
        }
    }
    walk(item);
    return found;
}

// Every eligible control under `body` a key can reach, in reading order. Not
// one folded away: hidden, sized to nothing, under something at zero opacity,
// or clipped out by a box that is not a list (a list scrolls to it instead).
function targets(body, eligible) {
    const found = collect(body, child => eligible(child) && child.width > 0 && child.height > 0 && inView(child, body));
    const at = new Map(found.map(t => [t, t.mapToItem(body, 0, 0)]));
    found.sort((a, b) => at.get(a).y - at.get(b).y || at.get(a).x - at.get(b).x);
    return found;
}

function inView(item, body) {
    for (let p = item.parent; p && p !== body; p = p.parent) {
        if (!p.clip || p.contentY !== undefined)
            continue;
        const r = item.mapToItem(p, 0, 0);
        if (r.y + item.height <= 0 || r.y >= p.height || r.x + item.width <= 0 || r.x >= p.width)
            return false;
    }
    return true;
}

// The control in `all` a key's step away from `cur`, or null. Up and Down go
// to the nearest control in the next row, keeping to the column where there
// is one; Left and Right stay in the row; Tab and Backtab go in reading order.
function neighbour(all, cur, key, body) {
    if (!all.length)
        return null;
    cur = cur && all.includes(cur) ? cur : null;
    const forward = key === Qt.Key_Down || key === Qt.Key_Right || key === Qt.Key_Tab;
    if (!cur)
        return forward ? all[0] : all[all.length - 1];
    if (key === Qt.Key_Tab || key === Qt.Key_Backtab)
        return all[all.indexOf(cur) + (forward ? 1 : -1)] ?? null;

    const box = t => {
        const p = t.mapToItem(body, 0, 0);
        return { l: p.x, r: p.x + t.width, cx: p.x + t.width / 2, cy: p.y + t.height / 2, h: t.height };
    };
    const c = box(cur);
    // In the same row: centres closer than half the shorter one's height.
    const sameRow = b => Math.abs(b.cy - c.cy) < Math.min(b.h, c.h) / 2;
    const others = all.filter(t => t !== cur).map(t => ({ t: t, b: box(t) }));

    if (key === Qt.Key_Left || key === Qt.Key_Right) {
        const side = others.filter(o => sameRow(o.b) && (forward ? o.b.cx > c.cx : o.b.cx < c.cx));
        side.sort((a, b) => Math.abs(a.b.cx - c.cx) - Math.abs(b.b.cx - c.cx));
        return side[0]?.t ?? null;
    }

    // The nearest row that way, then whatever in it overlaps the column
    // (a full-width row overlaps every column), then the nearest centre.
    const ahead = others.filter(o => !sameRow(o.b) && (forward ? o.b.cy > c.cy : o.b.cy < c.cy));
    if (!ahead.length)
        return null;
    const nearest = ahead.reduce((m, o) => Math.abs(o.b.cy - c.cy) < Math.abs(m.b.cy - c.cy) ? o : m);
    const row = ahead.filter(o => Math.abs(o.b.cy - nearest.b.cy) < Math.min(o.b.h, nearest.b.h) / 2);
    const gap = b => Math.max(0, b.l - c.r, c.l - b.r);
    row.sort((a, b) => gap(a.b) - gap(b.b) || Math.abs(a.b.cx - c.cx) - Math.abs(b.b.cx - c.cx));
    return row[0].t;
}

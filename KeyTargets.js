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

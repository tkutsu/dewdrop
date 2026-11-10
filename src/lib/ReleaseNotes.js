// Only these release feeds get upstream note lookups.
var detectorVersion = 2;

function project(feed) {
    if (feed === "https://github.com/quickshell-mirror/quickshell/releases.atom")
        return "Quickshell";
    if (feed === "https://github.com/hyprwm/Hyprland/releases.atom")
        return "Hyprland";
    return "";
}

function release(feed, url, body, updated) {
    const name = project(feed);
    const repo = name === "Quickshell" ? "quickshell-mirror/quickshell" : "hyprwm/Hyprland";
    const prefix = "https://github.com/" + repo + "/releases/tag/";
    const tag = url.startsWith(prefix) ? url.slice(prefix.length) : "";
    if (!name || !/^v?\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(tag))
        return null;
    const path = "/" + repo + "/blob/" + tag + "/changelog/" + tag + ".md";
    const linked = body.includes('href="' + path + '"') || body.includes('href="https://github.com' + path + '"');
    return {project: name, tag: tag, body: body, updated: updated, status: "loading",
        breaking: false, excerpt: "", notesUrl: name === "Quickshell" && linked
            ? "https://raw.githubusercontent.com/" + repo + "/" + tag + "/changelog/" + tag + ".md" : ""};
}

// Keep only the article, excluding the site's menus and related posts.
function article(html) {
    return html.match(/<article\b[^>]*>([\s\S]*?)<\/article>/i)?.[1] ?? "";
}

function plain(value) {
    return value.replace(/<!--[\s\S]*?-->/g, " ")
        .replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi, " ")
        .replace(/<[^>]*>/g, " ").replace(/&#x([\da-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
        .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
        .replace(/&(?:nbsp|amp|lt|gt|quot|apos);/g, e => ({"&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&apos;": "'"})[e])
        .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1").replace(/[`*]/g, "").replace(/^#{1,6}\s+/gm, "")
        .replace(/\s+/g, " ").trim();
}

// Upstream can declare a retired config or API in prose without a special heading.
function retirements(body, markdown) {
    const blocks = markdown ? body.split(/\n\s*\n/) : (body.match(/<(?:p|li)\b[^>]*>[\s\S]*?<\/(?:p|li)>/gi) ?? []);
    const subject = "(?:configs?|configurations?|config(?:uration)? (?:files?|options?|syntax)|APIs?|interfaces?|protocols?)";
    const unsupported = new RegExp("\\b" + subject + "\\s+(?:(?:is|are)\\s+no longer supported|(?:has|have)\\s+been\\s+(?:removed|dropped))\\b", "i");
    const dropped = /\bsupport for\s+[^.!?]{1,100}\s+(?:has been|is)\s+(?:removed|dropped)\b/i;
    return blocks.map(plain).filter(block => unsupported.test(block) || dropped.test(block));
}

// Named sections and explicit retirement statements both declare incompatibility.
function examine(body, markdown) {
    const clean = body.replace(/<!--[\s\S]*?-->/g, "").replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi, "");
    const pattern = markdown ? /^(#{1,6})\s+(.+?)\s*#*\s*$/gm : /<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi;
    const headings = [];
    let match;
    while ((match = pattern.exec(clean)) !== null)
        headings.push({level: markdown ? match[1].length : Number(match[1]), title: plain(match[2]), start: match.index, end: pattern.lastIndex});
    const excerpts = [];
    for (let i = 0; i < headings.length; i++) {
        const h = headings[i];
        if (!/^(?:breaking changes?|migration(?: guide| notes)?|incompatible changes?|backward[s]?[ -]incompatible changes?)\s*:?$/i.test(h.title))
            continue;
        const next = headings.slice(i + 1).find(n => n.level <= h.level);
        const section = plain(clean.slice(h.end, next ? next.start : clean.length));
        if (section && !/^(?:none\b|no (?:breaking|incompatible) changes?\b|not applicable\b|n\/a\b)/i.test(section))
            excerpts.push(section);
    }
    if (!excerpts.length)
        excerpts.push(...retirements(clean, markdown));
    return {valid: headings.length > 0 || excerpts.length > 0 || (markdown && /^initial release\b/i.test(clean.trim())),
        breaking: excerpts.length > 0, excerpt: excerpts.join(" ").slice(0, 600), summary: plain(clean).slice(0, 600)};
}

// Patch releases without an article still use their own full release notes.
function newsUrl(release, items) {
    const version = release.tag.replace(/^v/, "");
    const found = items.find(item => {
        const match = item.title.match(/\b(\d+\.\d+(?:\.\d+)?)\b/);
        return match && (match[1].split(".").length === 2 ? match[1] + ".0" : match[1]) === version
            && /^https:\/\/hypr\.land\/news\/[\w-]+\/?$/.test(item.url);
    });
    return found?.url ?? "";
}

function reusable(entry, release, now) {
    return entry && entry.detectorVersion === detectorVersion && entry.updated === release.updated
        && now - entry.checkedAt < (entry.status === "ready" ? 6 * 3600000 : 15 * 60000);
}

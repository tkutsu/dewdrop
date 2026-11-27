.pragma library
.import "EmailEntities.js" as EmailEntities

// A mail as text: the readable part of Gmail's payload, decoded, its markup
// gone, its quoted history cut, and its links kept for the reader to draw.
// Everything here takes text in and gives text back; Email.qml fetches.

// How much of a part is read, in base64 characters (about 384 KB): all
// of this runs on the bar's own thread, and the sender sets the size.
// Far more text than the reader shows; a newsletter's markup is the bulk.
var partLimit = 512 * 1024;

// A part's base64url body as the reader shows it, "" when nothing is left.
// Some senders write a plain part's letters as entities too (ΔΕΗ's Greek,
// "&Alpha;&gamma;…"), so it is unescaped like an HTML one.
function body(data, html) {
    const text = utf8(unbase64(data.slice(0, partLimit)));
    return unquote(tidy(html ? untag(text) : unentity(text)));
}

// Gmail sends the snippet HTML-escaped, apostrophes included.
function unentity(text) {
    return text.replace(/&(#(?:x[0-9a-f]+|\d+)|[a-z][a-z0-9]+);/gi, function (all, code) {
        if (code[0] !== "#")
            return Object.prototype.hasOwnProperty.call(EmailEntities.named, code) ? EmailEntities.named[code] : all;
        let n = code[1].toLowerCase() === "x" ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10);
        if (n === 0 || n > 0x10ffff || (n >= 0xd800 && n <= 0xdfff))
            return "\ufffd";
        // HTML's legacy numeric references use Windows-1252 in this range.
        const legacy = [0x20ac,0x81,0x201a,0x192,0x201e,0x2026,0x2020,0x2021,0x2c6,0x2030,0x160,0x2039,0x152,0x8d,0x17d,0x8f,0x90,0x2018,0x2019,0x201c,0x201d,0x2022,0x2013,0x2014,0x2dc,0x2122,0x161,0x203a,0x153,0x9d,0x17e,0x178];
        if (n >= 0x80 && n <= 0x9f)
            n = legacy[n - 0x80];
        return String.fromCodePoint(n);
    });
}

// Ignore file attachments when choosing the message's readable MIME part.
function mimePart(p, type) {
    if (!p || p.filename || (p.headers ?? []).some(h => h.name.toLowerCase() === "content-disposition" && /^attachment\b/i.test(h.value)))
        return null;
    if (p.mimeType === type && (p.body?.data || p.body?.attachmentId))
        return p;
    for (const child of p.parts ?? []) {
        const found = mimePart(child, type);
        if (found)
            return found;
    }
    return null;
}

// Gmail's base64url to bytes, as a list of numbers.
function unbase64(data) {
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    const bytes = [];
    let bits = 0;
    let value = 0;
    for (const c of data) {
        const v = alphabet.indexOf(c);
        if (v < 0)
            continue;
        value = (value << 6) | v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            bytes.push((value >> bits) & 0xff);
        }
    }
    return bytes;
}

// Invalid UTF-8 becomes a replacement character instead of crashing QML.
function utf8(bytes) {
    let out = "";
    for (let i = 0; i < bytes.length; i++) {
        const b = bytes[i];
        if (b < 0x80) {
            out += String.fromCharCode(b);
            continue;
        }
        const n = b >= 0xc2 && b <= 0xdf ? 1 : b >= 0xe0 && b <= 0xef ? 2 : b >= 0xf0 && b <= 0xf4 ? 3 : 0;
        let cp = b & (n === 1 ? 0x1f : n === 2 ? 0x0f : 0x07);
        let valid = n > 0;
        for (let k = 1; k <= n && valid; k++) {
            const c = bytes[i + k];
            valid = c !== undefined && (c & 0xc0) === 0x80;
            cp = (cp << 6) | (c & 0x3f);
        }
        if (!valid || cp < (n === 1 ? 0x80 : n === 2 ? 0x800 : 0x10000) || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff)) {
            out += "\ufffd";
            continue;
        }
        out += String.fromCodePoint(cp);
        i += n;
    }
    return out;
}

// Each element `open` finds, through the first `close` after it, put
// through `swap(match, inside)`: /<open>[\s\S]*?<close>/ in one pass.
// The regex looks again from every opening for a closing tag, to the end
// of the mail when there is none, so a sender's thousand unclosed spans
// held the bar for seconds. Here a closing tag missing after one opening
// is known to be missing after all the later ones. `close(match)` gives
// the closing tag as a pattern.
function elements(html, open, close, swap) {
    const after = ({});
    let out = "", from = 0, m;
    open.lastIndex = 0;
    while ((m = open.exec(html)) !== null) {
        const key = close(m);
        let end = after[key];
        if (end === undefined || end !== null && end.index < open.lastIndex) {
            const find = new RegExp(key, "gi");
            find.lastIndex = open.lastIndex;
            const found = find.exec(html);
            end = after[key] = found ? { index: found.index, end: find.lastIndex } : null;
        }
        if (end === null)
            continue;
        out += html.slice(from, m.index) + swap(m, html.slice(open.lastIndex, end.index));
        from = open.lastIndex = end.end;
    }
    return out + html.slice(from);
}

// Keep HTML link destinations, discard layout and non-content markup.
// A tag's insides are [^<>]: a `<` that never closes stops at the next
// tag rather than sending every pattern on to the end of the mail.
function untag(html) {
    const gone = () => "";
    const closing = m => "<\\/" + m[1] + "\\s*>";
    html = elements(html, /<!--/g, () => "-->", gone);
    html = elements(html, /<(style|script|head|title|noscript|template|svg|xml|object)\b[^<>]*>/gi, closing, gone);
    // What the sender hid: the preview line newsletters pad the inbox's
    // snippet with, and Outlook-only copies.
    html = elements(html, /<(div|span|p|td|table|a)\b[^<>]*\bstyle\s*=\s*["'][^"'<>]*(?:display\s*:\s*none|visibility\s*:\s*hidden|mso-hide\s*:\s*all|max-height\s*:\s*0(?:px)?\s*(?:;|["']))[^<>]*>/gi, closing, gone);
    html = html.replace(/<(?:div|blockquote)\b[^<>]*(?:\bclass\s*=\s*["'][^"'<>]*\bgmail_quote\b|\btype\s*=\s*["']?cite\b)[^<>]*>[\s\S]*$/i, "");
    html = elements(html, /<a\b([^<>]*)>/gi, () => "<\\/a\\s*>", function (m, label) {
        const href = m[1].match(/\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i);
        const url = href ? unentity(href[1] ?? href[2] ?? href[3]).trim() : "";
        return /^https?:\/\//i.test(url) ? "\ue000" + label + "\ue001" + url.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") + "\ue002" : label;
    });
    return unentity(html
        .replace(/\s+/g, " ")
        .replace(/<br\b[^<>]*>/gi, "\n")
        .replace(/<li\b[^<>]*>/gi, "\n• ")
        // A paragraph's end keeps a blank line after it (\u2029 until
        // the newlines are counted); a box's edge is only a line break.
        .replace(/<\/(?:p|h[1-6]|blockquote|table|ul|ol)\s*>|<hr\b[^<>]*>/gi, "\u2029")
        .replace(/<\/?(?:p|div|tr|li|h[1-6]|blockquote|table|ul|ol)\b[^<>]*>/gi, "\n")
        .replace(/<\/?(?:td|th)\b[^<>]*>/gi, " ")
        .replace(/<[^<>]+>/g, ""))
        .replace(/[^\S\n\u2029]+/g, " ").replace(/ *\n */g, "\n").replace(/\n{2,}/g, "\n")
        .replace(/\s*\u2029[\s\u2029]*/g, "\n\n").trim();
}

// A mail as text, whichever part it came from: no markup, nothing that
// takes no room, and the layout's scaffolding gone.
function tidy(text) {
    // A plain part that is really HTML.
    if (/<\/(?:p|div|td|tr|table|span|a|b|strong|font)\s*>|<br\s*\/?>/i.test(text))
        text = untag(text);
    return text
        // Tags left over or written out as entities.
        .replace(/<\/?(?:!doctype|html|head|body|meta|link|style|script|div|span|p|br|hr|table|tbody|thead|tfoot|tr|td|th|img|a|b|i|u|s|em|strong|font|center|ul|ol|li|h[1-6]|blockquote|pre|code|sup|sub|small|big|o:p|v:[a-z]+|xml)(?=[\s\/>])[^<>\n]*>/gi, "")
        // Characters that draw nothing: soft hyphens, zero-width spaces
        // and joiners (bar the emoji one), direction marks, the fillers a
        // preview line is padded with.
        .replace(/[\u00ad\u034f\u061c\u115f\u1160\u17b4\u17b5\u180e\u200b\u200c\u200e\u200f\u202a-\u202e\u2060-\u2064\u2066-\u206f\u3164\ufeff\uffa0]/g, "")
        // Gmail's stand-ins for pictures it did not inline.
        .replace(/\[(?:image|cid):[^\]\n]*\]/gi, "")
        // Rules drawn in characters.
        .replace(/^[^\S\n]*[-=_*~•·|#.]{3,}[^\S\n]*$/gm, "")
        .replace(/[^\S\n]+$/gm, "")
        .replace(/\n{3,}/g, "\n\n")
        .trim();
}

// Only generated anchors reach the UI; mail HTML never reaches Qt's renderer.
// A link in an HTML mail, as untag leaves it: \ue000 its words \ue001
// where it goes \ue002, private characters no mail text uses, for
// richText to make a link of and plain to spell out.
function linkPattern() {
    return /\ue000([^\ue001]*)\ue001([^\ue002]*)\ue002/g;
}

// A link says what it is rather than where it goes: an HTML link its
// words, "View online <https://\u2026>" in a plain mail its words, and a bare
// address its site. The address itself is a click away, drawn in `colour`.
function richText(text, colour) {
    const escape = value => value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    const site = url => url.replace(/^https?:\/\//i, "").replace(/^www\./i, "").split(/[\/?#]/)[0];
    const link = (url, words) => `<a href="${escape(/^www\./i.test(url) ? "https://" + url : url)}" style="color: ${colour}">${escape(words || site(url))}</a>`;
    const closers = { "<": ">", "[": "]", "(": ")" };
    const pattern = /(?:https?:\/\/|www\.)[^\s<>"\]\u200b-\u200d\ufeff]+/gi;
    const linkify = function (part) {
        let result = "";
        let offset = 0;
        let match;
        pattern.lastIndex = 0;
        while ((match = pattern.exec(part)) !== null) {
            let url = match[0].replace(/[.,;:!?]+$/, "");
            // Keep balanced parentheses in URLs, but leave prose punctuation out.
            while (url.endsWith(")") && (url.match(/\)/g) ?? []).length > (url.match(/\(/g) ?? []).length)
                url = url.slice(0, -1);
            const end = match.index + url.length;
            let before = part.slice(offset, match.index);
            let words = "";
            // "Label <url>": the bracket goes, and a short label on the
            // same line becomes the link.
            const close = closers[before.slice(-1)];
            if (close && part[end] === close) {
                before = before.slice(0, -1);
                const start = before.lastIndexOf("\n") + 1;
                const label = before.slice(start).trim().replace(/:$/, "");
                if (label.length > 0 && label.length <= 40) {
                    words = label;
                    before = before.slice(0, start) + before.slice(start).match(/^\s*/)[0];
                }
            }
            result += escape(before) + link(url, words);
            offset = end + (close && part[end] === close ? 1 : 0);
        }
        return result + escape(part.slice(offset));
    };
    let result = "";
    let offset = 0;
    const marked = linkPattern();
    let match;
    while ((match = marked.exec(text)) !== null) {
        result += linkify(text.slice(offset, match.index));
        const words = match[1].trim();
        result += /^https?:\/\//i.test(match[2]) ? link(match[2], words === match[2] ? "" : words) : escape(match[1]);
        offset = match.index + match[0].length;
    }
    return "<span style=\"white-space: pre-wrap\">" + (result + linkify(text.slice(offset))).replace(/\n/g, "<br>") + "</span>";
}

// The same text for a reader that shows no links: "label (url)".
function plain(text) {
    return text.replace(linkPattern(),
        (all, words, url) => !words.trim() || words.trim() === url ? url : `${words} (${url})`);
}

// The mail without what it is replying to: everything from the
// "On … wrote:" line down, which mail clients often wrap onto a second
// line, and any line quoted with ">".
function unquote(text) {
    const lines = text.replace(/\r\n?/g, "\n").replace(/[\u200b\ufeff]/g, "").replace(/[\u00a0\u202f]/g, " ").split("\n");
    const kept = [];
    const attribution = /^\s*(On|Στις) .+(wrote|έγραψε):\s*$/;
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (attribution.test(line) || attribution.test(line + " " + (lines[i + 1] ?? "")))
            break;
        if (/^\s*>/.test(line))
            continue;
        kept.push(line.replace(/\s+$/, ""));
    }
    return kept.join("\n").replace(/\n{3,}/g, "\n\n").trim();
}

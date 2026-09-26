pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Unread Gmail, as a list the popup can show and open.
//
// Read through the Gmail API on the shared Google sign-in (Google.qml), which
// replaced an IMAP tool that could only say how many: a count has nothing to
// click. Threads rather than messages, because that is how Gmail itself shows
// the inbox — three unread replies in one conversation are one row, and one
// thing to open.
//
// A poll is one list call, plus one call per thread whose history moved since
// it was last read. Only the first few threads are read in full, since those
// are all the popup has room for; the rest are counted and nothing more.
GoogleService {
    id: root

    readonly property string api: "https://gmail.googleapis.com/gmail/v1/users/me"
    readonly property string web: "https://mail.google.com/mail/u/0/"

    service: "Gmail"
    // Mail is the one thing on the bar you might be sat waiting for.
    pollMs: 30000

    onFetch: root.fetchThreads()

    // --- state ---------------------------------------------------------------
    // The rows the popup draws, newest first, each {id, message, from,
    // subject, snippet, at, replyTo, all, subjectRaw} — the last three for
    // answering it (see reply).
    property var threads: []
    // Every unread thread in the inbox, read in full or not. What the badge
    // counts.
    property int total: 0
    property string snapshot: ""

    // How many threads are read in full: the popup's cap and a few over, so a
    // row opened from the popup has one ready to take its place.
    readonly property int detailed: 12

    // Thread id → {historyId, row}. A thread's history id moves whenever
    // anything in it does, so a matching one means the row read last time is
    // still true and need not be asked for again.
    property var cache: ({})

    // Thread id → when it was opened from the popup. Gmail marks a thread
    // read when it is opened, but a poll in the few seconds before that lands
    // would put the row straight back; it stays out until a poll no longer
    // lists it, or for two minutes if it never goes (Gmail set not to mark on
    // open, say).
    property var opened: ({})
    readonly property int openedMs: 2 * 60000

    // Message id → its text, read when a row is opened in the popup. Kept
    // for the session: a mail does not change once sent.
    property var bodies: ({})

    // The account's own address, so a reply to all does not copy yourself in.
    property string me: ""

    // Replies from an earlier poll that land after a later one began are
    // dropped, or a slow one could put an opened row back.
    property int generation: 0

    readonly property int count: root.total
    readonly property string icon: count > 0 ? Theme.glyph.mailUnread : Theme.glyph.mailRead
    readonly property string label: !root.loaded || root.count === 0 ? "" : String(Math.min(root.count, 99))

    readonly property string tooltip: {
        if (!root.configured)
            return "Gmail not connected\nRun ~/_scripts/gtasks-setup";
        if (root.trouble !== "")
            return root.trouble;
        if (!root.loaded)
            return "Connecting…";
        return root.count === 0 ? "No unread mail" : `${root.count} unread`;
    }

    // --- reading -------------------------------------------------------------
    function fetchThreads(): void {
        if (root.me === "")
            root.send("GET", `${root.api}/profile?fields=emailAddress`, null, function (body) {
                root.me = (body?.emailAddress ?? "").toLowerCase();
            });
        root.generation += 1;
        const gen = root.generation;
        const url = `${root.api}/threads?labelIds=INBOX&labelIds=UNREAD&maxResults=100&fields=threads(id,historyId,snippet)`;
        root.send("GET", url, null, function (body) {
            if (gen !== root.generation)
                return;
            const listed = body?.threads ?? [];

            const now = Date.now();
            const still = ({});
            for (const t of listed)
                if (root.opened[t.id] && now - root.opened[t.id] < root.openedMs)
                    still[t.id] = root.opened[t.id];
            root.opened = still;

            const unread = listed.filter(t => !root.opened[t.id]);
            const wanted = unread.slice(0, root.detailed);
            const stale = wanted.filter(t => root.cache[t.id]?.historyId !== t.historyId);

            // Every stale thread asked for at once, and published together
            // when the last one lands, for the reason GoogleService.gather
            // gives: a list filled in reply by reply reorders itself under the
            // pointer.
            if (stale.length === 0) {
                root.publish(unread, wanted);
                return;
            }
            let outstanding = stale.length;
            const landed = function () {
                outstanding--;
                if (outstanding === 0 && gen === root.generation)
                    root.publish(unread, wanted);
            };
            for (const t of stale)
                root.send("GET", `${root.api}/threads/${t.id}?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=To&metadataHeaders=Cc&metadataHeaders=Reply-To&fields=messages(id,labelIds,internalDate,payload/headers)`, null, function (thread) {
                    root.cache[t.id] = {
                        historyId: t.historyId,
                        row: root.rowOf(t, thread)
                    };
                    landed();
                }, function (why, status) {
                    root.fail(why, status);
                    landed();
                });
        });
    }

    function publish(unread: var, wanted: var): void {
        // Only what is still listed is kept, so the cache is never bigger
        // than the inbox's unread.
        const kept = ({});
        for (const t of unread)
            if (root.cache[t.id])
                kept[t.id] = root.cache[t.id];
        root.cache = kept;

        const rows = wanted.filter(t => kept[t.id]).map(t => kept[t.id].row);
        // Replaced only when something moved, so a poll that changed nothing
        // does not rebuild the popup's rows under the pointer (see Tasks).
        const next = JSON.stringify(rows);
        if (next !== root.snapshot) {
            root.snapshot = next;
            root.threads = rows;
        }
        root.total = unread.length;
        root.loaded = true;
    }

    // A thread as a row: who wrote the newest unread message in it, what it
    // is about, and when. The newest unread rather than the first, because
    // that is the one waiting; the last message if none is marked, which is
    // a thread Gmail lists as unread for a message it has since hidden.
    function rowOf(listed: var, thread: var): var {
        const messages = thread?.messages ?? [];
        const unread = messages.filter(m => (m.labelIds ?? []).includes("UNREAD"));
        const m = unread.length > 0 ? unread[unread.length - 1] : messages[messages.length - 1];
        const header = name => (m?.payload?.headers ?? []).find(h => h.name.toLowerCase() === name)?.value ?? "";
        const sender = root.addresses(header("from"));
        return {
            id: listed.id,
            message: m?.id ?? "",
            from: root.sayFrom(header("from")),
            subject: header("subject").trim() || "(no subject)",
            subjectRaw: header("subject").trim(),
            snippet: root.unentity(listed.snippet ?? ""),
            at: Number(m?.internalDate ?? 0),
            // Who a reply goes to, and who else a reply to all copies in.
            replyTo: root.addresses(header("reply-to")).concat(sender).slice(0, 1),
            all: sender.concat(root.addresses(header("to")), root.addresses(header("cc")))
        };
    }

    // The bare addresses in a header: "Ann <a@x.org>, b@y.org" → [a@x.org,
    // b@y.org]. Whatever looks like an address, which steps round the commas
    // a quoted display name can carry.
    function addresses(header: string): var {
        return (header.match(/[^\s<>",;:]+@[^\s<>",;:]+/g) ?? []).map(a => a.toLowerCase());
    }

    // "Ann Example <ann@example.com>" → "Ann Example". The address when there
    // is no name, and whatever came when it is neither.
    function sayFrom(from: string): string {
        const m = from.match(/^\s*"?([^"<]*?)"?\s*<([^>]+)>\s*$/);
        if (!m)
            return from.trim();
        return m[1].trim() !== "" ? m[1].trim() : m[2].trim();
    }

    // Gmail sends the snippet HTML-escaped, apostrophes included.
    function unentity(text: string): string {
        return text.replace(/&(#\d+|#x[0-9a-f]+|amp|lt|gt|quot|apos);/gi, function (all, code) {
            switch (code.toLowerCase()) {
            case "amp":
                return "&";
            case "lt":
                return "<";
            case "gt":
                return ">";
            case "quot":
                return "\"";
            case "apos":
                return "'";
            }
            const n = code[1].toLowerCase() === "x" ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10);
            return isNaN(n) ? all : String.fromCodePoint(n);
        });
    }

    // When, as the row says it: the time today, the day this week, the date
    // before that — the same reach Tasks.sayDay gives a day name.
    function sayWhen(ms: real): string {
        if (ms <= 0)
            return "";
        const at = new Date(ms);
        const day = root.dayString(at);
        if (day === root.today)
            return Qt.formatTime(at, "HH:mm");
        const weekAgo = root.dayString(new Date(Google.now.getFullYear(), Google.now.getMonth(), Google.now.getDate() - 6));
        if (day >= weekAgo)
            return Qt.locale().dayName(at.getDay(), Locale.ShortFormat).toLowerCase();
        return Qt.formatDate(at, "d MMM");
    }

    // --- reading one ---------------------------------------------------------
    // The text of a row's message, into `bodies` once it lands. The plain
    // part when the mail has one, and the HTML one with its tags taken off
    // when it does not; either way without the quoted history under it,
    // which is the thread the popup is not showing.
    function read(row: var): void {
        if (row.message === "" || root.bodies[row.message] !== undefined)
            return;
        root.authorised(function () {
            root.send("GET", `${root.api}/messages/${row.message}?format=full&fields=payload`, null, function (body) {
                const next = Object.assign({}, root.bodies);
                next[row.message] = root.textOf(body?.payload) || row.snippet;
                root.bodies = next;
            });
        });
    }

    function textOf(payload: var): string {
        const plain = root.part(payload, "text/plain");
        if (plain !== "")
            return root.unquote(plain);
        const html = root.part(payload, "text/html");
        return html !== "" ? root.unquote(root.untag(html)) : "";
    }

    // The first part of a MIME tree with this type, decoded.
    function part(p: var, type: string): string {
        if (!p)
            return "";
        if (p.mimeType === type && p.body?.data)
            return root.utf8(root.unbase64(p.body.data));
        for (const child of p.parts ?? []) {
            const found = root.part(child, type);
            if (found !== "")
                return found;
        }
        return "";
    }

    // Gmail's base64url to bytes, as a list of numbers.
    function unbase64(data: string): var {
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

    // Bytes to text. QML has no TextDecoder, and mail is UTF-8 all but
    // always; a byte that does not fit is passed through as itself.
    function utf8(bytes: var): string {
        let out = "";
        for (let i = 0; i < bytes.length; i++) {
            const b = bytes[i];
            let n = 0;
            let cp = b;
            if (b >= 0xf0 && b < 0xf8) {
                n = 3;
                cp = b & 0x07;
            } else if (b >= 0xe0) {
                n = 2;
                cp = b & 0x0f;
            } else if (b >= 0xc0) {
                n = 1;
                cp = b & 0x1f;
            }
            if (n > 0) {
                let ok = true;
                for (let k = 1; k <= n; k++) {
                    const c = bytes[i + k];
                    if (c === undefined || (c & 0xc0) !== 0x80) {
                        ok = false;
                        break;
                    }
                    cp = (cp << 6) | (c & 0x3f);
                }
                if (ok) {
                    out += String.fromCodePoint(cp);
                    i += n;
                    continue;
                }
                cp = b;
            }
            out += String.fromCharCode(cp);
        }
        return out;
    }

    function untag(html: string): string {
        return root.unentity(html.replace(/<(style|script|head)[\s\S]*?<\/\1>/gi, "").replace(/<br\s*\/?>/gi, "\n").replace(/<\/(p|div|tr|li|h[1-6])>/gi, "\n").replace(/<[^>]+>/g, "").replace(/&nbsp;/g, " "));
    }

    // The mail without what it is replying to: everything from the
    // "On … wrote:" line down, which mail clients often wrap onto a second
    // line, and any line quoted with ">".
    function unquote(text: string): string {
        const lines = text.replace(/\r/g, "").split("\n");
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

    // --- opening -------------------------------------------------------------
    // The PWA on the thread itself, and the row gone at once: Gmail marks it
    // read on open, and the poll that confirms that is up to 30s away.
    function open(thread: var): void {
        const mark = Object.assign({}, root.opened);
        mark[thread.id] = Date.now();
        root.opened = mark;
        root.threads = root.threads.filter(t => t.id !== thread.id);
        root.total = Math.max(0, root.total - 1);
        root.snapshot = "";
        Quickshell.execDetached([Quickshell.env("HOME") + "/_scripts/pwa-gmail.sh", `${root.web}#inbox/${thread.id}`]);
    }

    function openInbox(): void {
        Quickshell.execDetached([Quickshell.env("HOME") + "/_scripts/pwa-gmail.sh"]);
    }

    // Gmail has no address for its own reply box, so an answer is a compose
    // window filled in the way the reply box would be: to the sender (or to
    // everyone on it, less yourself), under "Re:" and the subject.
    function reply(row: var, all: bool): void {
        const to = all ? row.replyTo.concat(row.all) : row.replyTo;
        const seen = ({});
        const list = to.filter(a => {
            if (a === root.me || seen[a])
                return false;
            seen[a] = true;
            return true;
        });
        const subject = /^re:/i.test(row.subjectRaw) ? row.subjectRaw : "Re: " + row.subjectRaw;
        root.compose({
            to: list[0] ?? "",
            cc: list.slice(1).join(","),
            su: subject
        });
    }

    // A compose window in the Gmail app, with whatever fields are given.
    function compose(fields: var): void {
        const query = Object.keys(fields ?? {}).filter(k => fields[k]).map(k => `&${k}=${encodeURIComponent(fields[k])}`).join("");
        Quickshell.execDetached([Quickshell.env("HOME") + "/_scripts/pwa-gmail.sh", `${root.web}?view=cm&fs=1${query}`]);
    }

    // qs ipc call email …
    IpcHandler {
        target: "email"

        function refresh(): void {
            root.refresh();
        }

        function list(): string {
            if (!root.loaded)
                return root.trouble !== "" ? root.trouble : root.tooltip;
            const out = root.threads.map(t => `${root.sayWhen(t.at)}  ${t.from}  ·  ${t.subject}`);
            return out.length > 0 ? `${root.total} unread\n${out.join("\n")}` : "No unread mail";
        }
    }
}

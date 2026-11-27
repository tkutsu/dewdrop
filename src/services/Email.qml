pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.src.core
import "../lib/EmailText.js" as EmailText
import "../lib/Pages.js" as Pages

// Unread Gmail, as a list the popup can show and open.
//
// Read through the Gmail API on the shared Google sign-in (Google.qml), which
// replaced an IMAP tool that could only say how many: a count has nothing to
// click. Threads rather than messages, because that is how Gmail itself shows
// the inbox — three unread replies in one conversation are one row, and one
// thing to open.
//
// A poll is one list call, plus one call per thread whose history moved since
// it was last read. The first few threads are detailed initially; the popup
// asks for more as its load-more button reveals additional rows.
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
    // subject, snippet, at, messages}. `messages` is the chain waiting in the
    // thread, oldest first, each {id, from, at, snippet}; the row's own
    // message, from and at are its last.
    property var threads: []
    // Every unread thread in the inbox tabs that count, read in full or not.
    // What the badge counts.
    property int total: 0
    // The Gmail tabs that count (primary, updates, promotions, social,
    // forums), picked on the settings window's Mail page. None picked: the
    // whole inbox counts.
    readonly property var categories: Settings.mailCategories
    onCategoriesChanged: if (root.loaded) {
        root.morePending = true;
        root.flushMore();
    }
    // The rest of the inbox's unread, which the popup folds into one row.
    // Its threads are only detailed once that row is unfolded.
    property int other: 0
    // Thread id → "total" or "other": which count each unread thread of the
    // last poll went into. The rows are only the detailed few of them, and a
    // search turns up mail that is in neither.
    property var counted: ({})
    property var otherThreads: []
    property bool otherWanted: false
    onOtherWantedChanged: if (root.otherWanted && root.otherThreads.length < Math.min(root.other, root.detailed)) {
        root.morePending = true;
        root.flushMore();
    }
    property string snapshot: ""

    // What the popup did that has not reached Gmail yet, oldest first, each
    // {kind, row, list, wasOpen, said, also}. Every action from the popup
    // waits for it to close, so Undo takes them back one by one for as long
    // as it is open; the row has left the list already, so the wait costs
    // nothing. Closing the popup sends whatever is still waiting.
    property var pending: []
    // An undone row back in its list, for the popup to reopen it.
    signal restored(var row, bool wasOpen)

    // Thread metadata requested so far, plus a few spare rows to replace
    // threads marked read. Grows when the popup requests another batch.
    property int detailed: 12
    property bool morePending: false

    // Thread id → {historyId, row}. A thread's history id moves whenever
    // anything in it does, so a matching one means the row read last time is
    // still true and need not be asked for again.
    property var cache: ({})

    // Threads opened while a poll is in flight stay out of that poll's
    // result. The next poll trusts Gmail again, so marking a thread unread
    // in Gmail brings it back without a local suppression timeout.
    property var opened: ({})

    // Message id → its text, read when a row is opened in the popup. A mail
    // does not change once sent, so the newest bodyKeep are kept and an older
    // one reopened is simply read again.
    property var bodies: ({})
    readonly property int bodyKeep: 200
    property var reading: ({})
    property var readQueue: []
    property int bodyRequests: 0
    readonly property int bodyParallel: 4
    readonly property int headerParallel: 6

    // Replies from an earlier poll that land after a later one began are
    // dropped, or a slow one could put an opened row back.
    property int generation: 0

    readonly property int count: root.total
    readonly property string icon: count > 0 ? Theme.glyph.mailUnread : Theme.glyph.mailRead
    readonly property string label: !root.loaded || root.count === 0 ? "" : String(Math.min(root.count, 99))

    readonly property string tooltip: {
        if (!root.configured)
            return `Gmail not connected\nRun ${Google.setup}`;
        if (root.trouble !== "")
            return root.trouble;
        if (!root.loaded)
            return "Connecting…";
        const other = root.other > 0 ? ` · ${root.other} other` : "";
        return (root.count === 0 ? "No unread mail" : `${root.count} unread`) + other;
    }

    // Grow the metadata window on demand, after any current request chain.
    function loadMore(limit: int): void {
        if (limit <= root.threads.length)
            return;
        root.detailed = Math.max(root.detailed, limit + 4);
        root.morePending = true;
        root.flushMore();
    }

    function flushMore(): void {
        if (!root.morePending || root.loading)
            return;
        root.morePending = false;
        root.refresh();
    }

    onLoadingChanged: root.flushMore()

    // --- reading -------------------------------------------------------------
    // Two lists: the unread in the tabs that count, and every unread in the
    // inbox, of which the rest is `other`. Both in flight at once, and
    // nothing published until both are in. With no tabs picked the inbox is
    // the one list and there is no other.
    function fetchThreads(): void {
        root.generation += 1;
        const gen = root.generation;
        const current = () => gen === root.generation;
        let counted = null;
        let all = null;
        const both = function () {
            if (counted === null || all === null)
                return;
            // Hide a just-opened thread while Gmail catches up. Confirmation
            // clears the marker; a failed read is visible again after 30
            // seconds. A thread still waiting in the queue stays hidden however
            // long the list takes to agree.
            const seen = ({});
            for (const t of all)
                seen[t.id] = true;
            const waiting = ({});
            for (const p of root.pending)
                waiting[p.row.id] = true;
            const opened = ({});
            for (const [id, at] of Object.entries(root.opened))
                if (waiting[id] || (seen[id] && Date.now() - at < 30000))
                    opened[id] = at;
            root.opened = opened;

            const isCounted = ({});
            for (const t of counted)
                isCounted[t.id] = true;
            const unread = counted.filter(t => !root.opened[t.id]);
            const rest = all.filter(t => !isCounted[t.id] && !root.opened[t.id]);
            const wanted = unread.slice(0, root.detailed);
            const wantedOther = root.otherWanted ? rest.slice(0, root.detailed) : [];
            const stale = wanted.concat(wantedOther).filter(t => !t.historyId || root.cache[t.id]?.historyId !== t.historyId);

            // Published together when the last one lands, for the reason
            // GoogleService.gather gives: a list filled in reply by reply
            // reorders itself under the pointer.
            root.eachHeader(stale, function (t, thread) {
                root.cache[t.id] = {
                    historyId: t.historyId,
                    row: root.rowOf(t, thread)
                };
            }, () => root.publish(unread, wanted, rest, wantedOther), current);
        };
        if (root.categories.length > 0)
            root.listAll("&q=" + encodeURIComponent(root.categories.map(c => "category:" + c).join(" OR ")), current, listed => {
                counted = listed;
                both();
            });
        root.listAll("", current, listed => {
            all = listed;
            if (root.categories.length === 0)
                counted = listed;
            both();
        });
    }

    // Every unread thread in the inbox matching `query`, page by page, then
    // `then(listed)` once the last page is in.
    function listAll(query: string, current: var, then: var): void {
        const url = `${root.api}/threads?labelIds=INBOX&labelIds=UNREAD${query}&maxResults=500&fields=nextPageToken,threads(id,historyId,snippet)`;
        const listed = [];
        const seen = ({});
        Pages.walk((token, ok, fail) => root.send("GET", Pages.url(url, token), null, ok, fail), function (body) {
            if (!current())
                return false;
            for (const t of body?.threads ?? []) {
                if (t.id && !seen[t.id]) {
                    seen[t.id] = true;
                    listed.push(t);
                }
            }
        }, () => then(listed), function (why, status) {
            if (current())
                root.fail(why, status);
        });
    }

    // A thread's messages with only what a row needs: who, what, when,
    // which of them are unread, and how to leave the list it came from.
    function headersUrl(id: string): string {
        const headers = ["From", "Subject", "List-Unsubscribe", "List-Unsubscribe-Post"].map(h => `&metadataHeaders=${h}`).join("");
        return `${root.api}/threads/${id}?format=metadata${headers}&fields=messages(id,labelIds,internalDate,snippet,payload/headers)`;
    }

    function publish(unread: var, wanted: var, rest: var, wantedOther: var): void {
        // A row may have been opened while its metadata was in flight.
        const shown = t => !root.opened[t.id];
        unread = unread.filter(shown);
        rest = rest.filter(shown);
        // Only what is still listed is kept, so the cache is never bigger
        // than the inbox's unread.
        const kept = ({});
        for (const t of unread.concat(rest))
            if (root.cache[t.id])
                kept[t.id] = root.cache[t.id];
        root.cache = kept;

        const rowsOf = listed => listed.filter(t => shown(t) && kept[t.id]).map(t => kept[t.id].row).sort((a, b) => b.at - a.at);
        const rows = rowsOf(wanted);
        const others = rowsOf(wantedOther);
        // Replaced only when something moved, so a poll that changed nothing
        // does not rebuild the popup's rows under the pointer (see Tasks).
        const next = JSON.stringify([rows, others]);
        if (next !== root.snapshot) {
            root.snapshot = next;
            root.threads = rows;
            root.otherThreads = others;
        }
        root.total = unread.length;
        root.other = rest.length;
        const counted = ({});
        for (const t of unread)
            counted[t.id] = "total";
        for (const t of rest)
            counted[t.id] = "other";
        root.counted = counted;
        root.loaded = true;
        root.announce(rows);
    }

    // --- telling ---------------------------------------------------------
    // A card for each new mail that counts, through notify-send like
    // any other app, so it gets the notification server's own cards, Do Not
    // Disturb and centre. New is newer than anything a poll has shown
    // before, which a row turned up by "load more" never is. Nothing for the
    // first poll after the bar starts, which would announce the whole inbox,
    // nor while the popup is open and showing it anyway.
    property real newestSeen: -1
    property bool popupOpen: false
    // A card about several mails was clicked: the bar opens the popup.
    signal summoned

    function announce(rows: var): void {
        const before = root.newestSeen;
        root.newestSeen = Math.max(0, before, ...rows.map(r => r.at));
        if (before < 0 || root.popupOpen)
            return;
        const fresh = rows.filter(r => r.at > before && !root.opened[r.id]);
        if (fresh.length > 3)
            root.tell([`${fresh.length} new mails`, ""], ["--action=default=Open"], null, "");
        else
            for (const r of fresh.slice().reverse()) {
                const code = root.codeIn(r);
                const actions = ["--action=default=Open", "--action=archive=Archive", "--action=read=Mark read"];
                if (code)
                    actions.push(`--action=code=Copy ${code}`);
                const body = [r.subject, r.snippet].filter(s => s).join("\n");
                root.tell([r.from, root.escapeMarkup(body)], actions.concat([`--hint=string:x-gmail-thread:${r.id}`]), r, code);
            }
    }

    // One card. `--wait` keeps notify-send until it is answered, and the
    // action chosen is what it prints. The buttons act at once: by then the
    // card is gone, and there is nowhere left to offer an undo.
    function tell(text: var, options: var, row: var, code: string): void {
        if (!Tools.has("notify-send"))
            return;
        const command = ["notify-send", "--wait", "--app-name=Gmail", "--icon=Gmail-mail.google.com"].concat(options, ["--"], text);
        card.createObject(root, { command: command, row: row, code: code }).running = true;
    }

    function answered(chosen: string, row: var, code: string): void {
        if (!row) {
            if (chosen === "default")
                root.summoned();
            return;
        }
        if (chosen === "default")
            root.open(row);
        else if (chosen === "archive")
            root.archive(row);
        else if (chosen === "read")
            root.markRead(row);
        else if (chosen === "code") {
            root.copy(code);
            root.markRead(row);
        }
    }

    function escapeMarkup(text: string): string {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function copy(text: string): void {
        Quickshell.clipboardText = text;
    }

    // --- codes -----------------------------------------------------------
    // A one-time code in a mail: 4 to 8 digits, or 3 and 3 split by a space
    // or a dash, perhaps behind a letter prefix (G-123456), near a word that
    // says it is one. The nearest to such a word wins; a word after the code
    // ("123456 is your code") counts at half the reach of one before it.
    // Prices, years, times, dates and order numbers are not codes. Copied as
    // the digits alone, which is what every code field takes.
    function codeOf(text: string): string {
        if (!text)
            return "";
        const keyword = /(?:^|[^A-Za-z])(?:codes?|verification|verify|otp|passcode|pin|one[- ]?time|2fa)(?![A-Za-z])|κωδικ|επαλ[ηή]θευ/gi;
        const spots = [];
        let k;
        while ((k = keyword.exec(text)) !== null)
            spots.push(k.index);
        if (spots.length === 0)
            return "";
        const candidate = /(^|[^\w$€£#.,\/:+-])((?:[A-Z]{1,3}-)?(\d{3}[ -]\d{3}|\d{4,8}))(?![\w%$€£]|[.,\/:-]\d)/g;
        let best = "";
        let nearest = 81;
        let m;
        while ((m = candidate.exec(text)) !== null) {
            const at = m.index + m[1].length;
            const digits = m[3].replace(/\D/g, "");
            if (/^(19|20)\d\d$/.test(digits))
                continue;
            const before = text.slice(Math.max(0, at - 16), at);
            if (/(?:order|invoice|ref|reference|tracking|account|acct|no|παραγγελ\S*|αρ)\W{0,4}$/i.test(before) || /[$€£]\s?$/.test(before))
                continue;
            const distance = Math.min(...spots.map(s => at >= s ? at - s : (s - at) * 2));
            if (distance < nearest) {
                nearest = distance;
                best = digits;
            }
        }
        return best;
    }

    // A row's code: in its subject or snippet, or in its text once read.
    function codeIn(row: var): string {
        return row.code || root.codeOf(root.bodies[row.message] ?? "");
    }

    // --- the open mail's foot --------------------------------------------
    // The unsubscribe address a mail gives in List-Unsubscribe, when one is
    // on the web: mailto alone gets no button. One-click (RFC 8058, which
    // Gmail asks of bulk senders) when List-Unsubscribe-Post says so, and
    // only then is it done from here; otherwise the page is opened.
    function unsubscribeOf(list: string, post: string): var {
        const urls = (list.match(/<[^>]+>/g) ?? []).map(u => u.slice(1, -1).trim());
        const web = urls.find(u => /^https:\/\//i.test(u));
        return web ? { url: web, oneClick: /List-Unsubscribe\s*=\s*One-Click/i.test(post) } : null;
    }

    // The one-click POST. Straight to the sender, with no Google token on
    // it: that never leaves Google.
    function unsubscribe(row: var): void {
        const failed = () => root.trouble = `Unsubscribing from ${row.from} failed`;
        Http.request("POST", row.unsubscribe.url, "List-Unsubscribe=One-Click", { "Content-Type": "application/x-www-form-urlencoded" }, 30000, function (xhr) {
            if (xhr.status < 200 || xhr.status >= 400)
                failed();
        }, failed);
    }

    // Message id → its files, each {id, name, size, type}, read with its
    // text. Images placed in the text (a signature's logo) are not files.
    property var files: ({})
    // Attachment ids being saved now.
    property var saving: ({})

    function partsOf(payload: var): var {
        const found = [];
        const walk = function (p) {
            if (!p)
                return;
            const header = name => (p.headers ?? []).find(h => h.name.toLowerCase() === name)?.value ?? "";
            const placed = header("content-id") !== "" && /^\s*inline/i.test(header("content-disposition"));
            if (p.filename && p.body?.attachmentId && !placed)
                found.push({
                    id: p.body.attachmentId,
                    name: p.filename,
                    size: p.body.size ?? 0,
                    type: p.mimeType ?? ""
                });
            for (const child of p.parts ?? [])
                walk(child);
        };
        walk(payload);
        return found;
    }

    // Into the downloads folder, under a new name if its name is taken, then
    // opened. scripts/gmail-attachment fetches and writes it; the token goes
    // to it in its environment, where the process list does not show it.
    // Every attachment of a thread's open messages, each with the message
    // it hangs off: { message, part }.
    function partsIn(thread: var): var {
        const found = [];
        for (const m of thread?.messages ?? [])
            for (const part of root.files[m.id] ?? [])
                found.push({ message: m.id, part: part });
        return found;
    }

    // All of them at once. One is opened as a single save is; several open
    // the folder they landed in, once the last is down, rather than a window
    // each.
    function saveAll(parts: var): void {
        const due = parts.filter(p => !root.saving[p.part.id]);
        if (due.length === 1) {
            root.save(due[0].message, due[0].part);
            return;
        }
        let left = due.length;
        let folder = "";
        for (const p of due)
            root.save(p.message, p.part, path => {
                if (path)
                    folder = path.slice(0, path.lastIndexOf("/"));
                if (--left === 0 && folder)
                    Quickshell.execDetached(["xdg-open", folder]);
            });
    }

    // `landed` hears where the file went ("" when it did not), and opens
    // it unless told otherwise.
    function save(message: string, part: var, landed: var): void {
        if (root.saving[part.id])
            return;
        root.saving = Object.assign({}, root.saving, { [part.id]: true });
        const done = function () {
            const next = Object.assign({}, root.saving);
            delete next[part.id];
            root.saving = next;
        };
        const then = landed ?? (path => {
            if (path)
                Quickshell.execDetached(["xdg-open", path]);
        });
        root.authorised(() => saver.createObject(root, {
                command: [Quickshell.shellPath("scripts/gmail-attachment"), message, part.id, part.name],
                environment: { GMAIL_TOKEN: Google.accessToken, GMAIL_DOWNLOAD_DIR: Settings.downloadsDir },
                part: part,
                done: done,
                landed: then
            }).running = true, function (why, status) {
            done();
            then("");
            root.fail(why, status);
        });
    }

    // A thread as a row: who wrote the newest unread message in it, what it
    // is about, and when. The newest unread rather than the first, because
    // that is the one waiting; the last message if none is marked, which is
    // a thread Gmail lists as unread for a message it has since hidden. The
    // unread ones before it come along as the chain, so a row opened reads
    // them all and not just the last word.
    function rowOf(listed: var, thread: var): var {
        const messages = (thread?.messages ?? []).slice().sort((a, b) => Number(a.internalDate ?? 0) - Number(b.internalDate ?? 0));
        const unread = messages.filter(m => (m.labelIds ?? []).includes("UNREAD"));
        const chain = unread.length > 0 ? unread : messages.slice(-1);
        const m = chain[chain.length - 1];
        const header = (msg, name) => (msg?.payload?.headers ?? []).find(h => h.name.toLowerCase() === name)?.value ?? "";
        const subject = header(m, "subject").trim() || "(no subject)";
        const snippet = EmailText.unentity(listed.snippet ?? "");
        return {
            id: listed.id,
            message: m?.id ?? "",
            // The thread's newest message, read or not: where a star goes.
            last: messages[messages.length - 1]?.id ?? "",
            from: root.sayFrom(header(m, "from")),
            address: root.addressOf(header(m, "from")),
            subject: subject,
            snippet: snippet,
            code: root.codeOf(subject + "\n" + snippet),
            unsubscribe: root.unsubscribeOf(header(m, "list-unsubscribe"), header(m, "list-unsubscribe-post")),
            at: Number(m?.internalDate ?? 0),
            unread: unread.length > 0,
            starred: messages.some(m => (m.labelIds ?? []).includes("STARRED")),
            messages: chain.map(c => ({
                        id: c.id,
                        from: root.sayFrom(header(c, "from")),
                        at: Number(c.internalDate ?? 0),
                        snippet: EmailText.unentity(c.snippet ?? "")
                    }))
        };
    }

    // "Ann Example <ann@example.com>" → "Ann Example". The address when there
    // is no name, and whatever came when it is neither.
    function sayFrom(from: string): string {
        const m = from.match(/^\s*"?([^"<]*?)"?\s*<([^>]+)>\s*$/);
        if (!m)
            return from.trim();
        return m[1].trim() !== "" ? m[1].trim() : m[2].trim();
    }

    // "Ann Example <ann@example.com>" → "ann@example.com"; a bare address
    // as it came.
    function addressOf(from: string): string {
        const m = from.match(/<([^>]+)>/);
        return (m ? m[1] : from).trim().toLowerCase();
    }

    // The monogram's letters: the first of the first two words of the name,
    // or the address's first letter when there is no name. Words without a
    // letter in them ("Ann | Example Ltd") are skipped. A letter is told by
    // having a case, which QML's regular expressions cannot say directly
    // (no \p{L}), plus digits and the scripts that have no case.
    function initials(name: string): string {
        const lettered = c => /[0-9぀-ヿ㐀-鿿가-힯]/.test(c) || c.toLowerCase() !== c.toUpperCase();
        const words = name.replace(/@.*$/, "").split(/[\s._-]+/).map(w => Array.from(w).find(lettered) ?? "").filter(c => c !== "");
        return words.slice(0, 2).join("").toLocaleUpperCase();
    }

    // Which of Theme.monogramTones a sender wears, the same every time.
    function toneOf(address: string, tones: int): int {
        let h = 0;
        for (const c of address)
            h = (h * 31 + c.codePointAt(0)) >>> 0;
        return h % tones;
    }

    // When, as the row says it: the time today, the day this week, the date
    // before that — the same reach Tasks.sayDay gives a day name.
    function sayWhen(ms: real): string {
        if (ms <= 0)
            return "";
        const at = new Date(ms);
        const day = root.dayString(at);
        if (day === root.today)
            return Settings.sayTime(at);
        const weekAgo = root.dayString(new Date(Google.now.getFullYear(), Google.now.getMonth(), Google.now.getDate() - 6));
        if (day >= weekAgo)
            return Qt.locale().dayName(at.getDay(), Locale.ShortFormat).toLowerCase();
        // And the year once it is not this one, or last December would read
        // as coming after this July.
        return Qt.formatDate(at, at.getFullYear() === Google.now.getFullYear() ? "d MMM" : "d MMM yyyy");
    }

    // sayWhen as rich text for a popup line, a time today with the bar's AM/PM.
    function whenMarkup(ms: real, pixelSize: int): string {
        const at = new Date(ms);
        if (ms > 0 && root.dayString(at) === root.today)
            return Settings.timeMarkup(Settings.hourDisplay(at), pixelSize);
        return root.sayWhen(ms).replace(/&/g, "&amp;").replace(/</g, "&lt;");
    }

    // --- searching -----------------------------------------------------------
    // The launcher's @ mode past the prefix: the whole mailbox, read or not,
    // in Gmail's own search syntax ("from:ann has:attachment"), because the
    // API takes the same q= the search box does. The answer is tagged with
    // the query it was for, {q, rows, trouble}, the way the calculator's is,
    // so it only ever shows against that query.
    //
    // `starredFirst` puts the starred matches on top — asked for separately,
    // so a starred mail that is not among the newest few still makes the
    // list. The launcher's "recent" view (a bare "@" with nothing unread) is
    // the same search without it.
    property var found: null
    property int searches: 0
    readonly property int searchMax: 10

    function search(q: string, starredFirst: bool): void {
        searchRetry.stop();
        // A sender lookup is a timeline, including when it contains starred mail.
        root.runSearch(q, starredFirst && !/(?:^|[\s({])-?from:/i.test(q), 0);
    }

    Timer {
        id: searchRetry
        property var again: null
        onTriggered: if (searchRetry.again) searchRetry.again()
    }

    function runSearch(q: string, starredFirst: bool, attempt: int): void {
        root.searches += 1;
        const gen = root.searches;
        const current = () => gen === root.searches;
        let broken = false;
        const alive = () => current() && !broken;
        // Newest first by the date each row shows, starred ones on top when
        // asked. Gmail's own order goes by the message that matched, which a
        // row showing the thread's newest one makes look shuffled.
        const answer = (rows, trouble) => {
            if (current())
                root.found = {
                    q: q,
                    at: Date.now(),
                    rows: rows.sort((a, b) => (starredFirst ? b.starred - a.starred : 0) || b.at - a.at),
                    trouble: trouble
                };
        };
        const failed = function (why, status, reason) {
            if (!alive())
                return;
            broken = true;
            const limited = status === 429 || (status === 403 && /^(?:userRateLimitExceeded|rateLimitExceeded|quotaExceeded|RESOURCE_EXHAUSTED)$/.test(reason ?? ""));
            const temporary = limited || status === 0 || status === 408 || status >= 500;
            if (temporary && attempt < 3) {
                answer([], limited ? "Gmail rate limit reached. Trying again..." : "Gmail search unavailable. Trying again...");
                searchRetry.interval = 2000 * Math.pow(2, attempt);
                searchRetry.again = () => { if (current()) root.runSearch(q, starredFirst, attempt + 1); };
                searchRetry.restart();
                return;
            }
            const disabled = status === 403 && /^(?:accessNotConfigured|SERVICE_DISABLED|serviceDisabled)$/.test(reason ?? "");
            answer([], disabled ? "Gmail API not enabled in the Google console"
                : limited ? "Gmail rate limit reached. Try again shortly."
                : reason ? `${why} (${reason})` : why);
        };
        // Gmail lists newest first.
        const list = (query, then) => root.send("GET", `${root.api}/threads?maxResults=${root.searchMax}&q=${encodeURIComponent(query)}&fields=threads(id,historyId,snippet)`, null, body => {
            if (alive())
                then(body?.threads ?? []);
        }, failed);

        if (!starredFirst) {
            list(q, listed => root.detail(listed, rows => answer(rows, ""), failed, alive));
            return;
        }
        // Bracketed, so "a OR b" gains the star as a whole rather than
        // on its last word.
        let starred = null;
        let all = null;
        const merge = function () {
            if (starred === null || all === null)
                return;
            const seen = ({});
            for (const t of starred)
                seen[t.id] = true;
            const listed = starred.concat(all.filter(t => !seen[t.id])).slice(0, root.searchMax);
            root.detail(listed, rows => answer(rows, ""), failed, alive);
        };
        list(`(${q}) is:starred`, l => {
            starred = l;
            merge();
        });
        list(q, l => {
            all = l;
            merge();
        });
    }

    // Listed threads to rows, in the order given, kept by slot rather than
    // by arrival. A thread the poll has already read costs nothing.
    function detail(listed: var, then: var, failed: var, alive: var): void {
        const rows = listed.map(t => {
            const c = root.cache[t.id];
            return c && t.historyId && c.historyId === t.historyId ? c.row : null;
        });
        const missing = listed.filter((t, i) => rows[i] === null);
        root.eachHeader(missing, (t, thread) => rows[listed.indexOf(t)] = root.rowOf(t, thread), () => then(rows.filter(r => r)), alive ?? (() => true), failed);
    }

    // Each thread's headers, a few requests at a time: after "load more" a
    // poll can find a couple of hundred threads stale. `done` runs once all
    // have landed or failed, and nothing more is asked once `alive` goes false.
    function eachHeader(threads: var, each: var, done: var, alive: var, failed: var): void {
        let next = 0;
        let outstanding = threads.length;
        if (outstanding === 0) {
            done();
            return;
        }
        const start = function () {
            if (next >= threads.length || !alive())
                return;
            const t = threads[next++];
            const settle = function () {
                if (!alive())
                    return;
                if (--outstanding === 0)
                    done();
                else
                    start();
            };
            root.send("GET", root.headersUrl(t.id), null, function (thread) {
                if (alive())
                    each(t, thread);
                settle();
            }, function (why, status, reason) {
                if (alive())
                    (failed ?? root.fail)(why, status, reason);
                settle();
            });
        };
        for (let i = 0; i < root.headerParallel; i++)
            start();
    }

    // --- reading one ---------------------------------------------------------
    // The text of each message in a row's chain, into `bodies` as it lands.
    // The plain part when the mail has one, and the HTML one with its tags
    // taken off when it does not; either way without the quoted history
    // under it, which is the chain the popup already shows above it.
    function read(row: var): void {
        const queued = root.readQueue.slice();
        for (const m of row.messages ?? []) {
            if (m.id && root.bodies[m.id] === undefined && !root.reading[m.id]) {
                root.reading[m.id] = true;
                queued.push(m);
            }
        }
        root.readQueue = queued;
        root.readNext();
    }

    // Bound body requests even when one unread conversation has many replies.
    function readNext(): void {
        while (root.bodyRequests < root.bodyParallel && root.readQueue.length > 0) {
            const m = root.readQueue[0];
            root.readQueue = root.readQueue.slice(1);
            root.bodyRequests++;
            const finished = function () {
                delete root.reading[m.id];
                root.bodyRequests--;
                root.readNext();
            };
            const failed = function (why, status) {
                root.fail(why, status);
                finished();
            };
            root.send("GET", `${root.api}/messages/${m.id}?format=full&fields=payload`, null, function (body) {
                const parts = root.partsOf(body?.payload);
                root.loadText(m.id, body?.payload, function (text) {
                    // A new object, so bindings on `bodies` see the change.
                    const next = ({});
                    for (const id of Object.keys(root.bodies).slice(1 - root.bodyKeep))
                        next[id] = root.bodies[id];
                    next[m.id] = text || m.snippet;
                    root.bodies = next;
                    if (parts.length > 0)
                        root.files = Object.assign({}, root.files, { [m.id]: parts });
                    const files = ({});
                    for (const id of Object.keys(next))
                        if (id in root.files)
                            files[id] = root.files[id];
                    root.files = files;
                    finished();
                }, failed);
            }, failed);
        }
    }

    // Large inline bodies live behind Gmail's attachment endpoint too.
    function loadText(id: string, payload: var, then: var, failed: var): void {
        const types = ["text/plain", "text/html"];
        const attempt = function (index) {
            if (index === types.length) {
                then("");
                return;
            }
            const p = EmailText.mimePart(payload, types[index]);
            if (!p) {
                attempt(index + 1);
                return;
            }
            const decoded = function (data) {
                const clean = EmailText.body(data ?? "", types[index] === "text/html");
                if (clean !== "")
                    then(clean);
                else
                    attempt(index + 1);
            };
            if (p.body.data)
                decoded(p.body.data);
            else
                root.send("GET", `${root.api}/messages/${id}/attachments/${encodeURIComponent(p.body.attachmentId)}?fields=data`, null, body => decoded(body?.data), failed);
        };
        attempt(0);
    }

    // --- opening -------------------------------------------------------------
    // Gmail on the thread itself, and an unread row gone at once: Gmail
    // marks it read on open, and the poll that confirms that is up to 30s
    // away. A read one, which only a search turns up, was never counted;
    // the cache is the poll's unread, whatever its labels say.
    function open(thread: var): void {
        if (thread.unread || root.cache[thread.id])
            root.drop(thread);
        Quickshell.execDetached(Settings.webApp("gmail", `${root.web}#inbox/${thread.id}`, root.web));
    }

    // Read without opening it, at once: the launcher's reader and a
    // notification's button, which have nowhere to show an undo. The popup
    // goes through act() instead.
    function markRead(thread: var): void {
        root.drop(thread);
        root.perform("read", thread);
    }

    function archive(thread: var): void {
        root.drop(thread);
        root.perform("archive", thread);
    }

    // --- acting ----------------------------------------------------------
    // What each verb says in the popup's foot while it waits.
    readonly property var said: ({
            archive: "Archived",
            read: "Marked read",
            star: "Starred",
            unstar: "Unstarred"
        })

    // A verb from the popup: done here at once, sent to Gmail as it closes.
    // Archive and read take the row out of its list; a star stays and only
    // turns. `options` may carry wasOpen (the row was the open one, so an
    // undo opens it again), said (the undo button's words, for a compound action)
    // and also (more to send with it, as one undoable thing: called with
    // the row when the wait is over).
    function act(kind: string, row: var, options: var): void {
        const o = options ?? {};
        const list = root.otherThreads.some(t => t.id === row.id) ? "otherThreads" : "threads";
        const entry = {
            kind: kind,
            row: row,
            list: list,
            wasOpen: !!o.wasOpen,
            said: o.said ?? root.said[kind],
            also: o.also ?? null
        };
        if (kind === "star" || kind === "unstar")
            root.restar(row.id, kind === "star");
        else
            root.drop(row);
        root.pending = root.pending.concat([entry]);
    }

    // Take back the latest action that has not gone yet.
    function undo(): void {
        const entry = root.pending[root.pending.length - 1];
        if (!entry)
            return;
        root.pending = root.pending.slice(0, -1);
        if (entry.kind === "star" || entry.kind === "unstar")
            root.restar(entry.row.id, entry.kind !== "star");
        else
            root.restore(entry);
    }

    // Everything still waiting, now: the popup closing.
    function flush(): void {
        const all = root.pending;
        root.pending = [];
        for (const entry of all)
            root.commit(entry);
    }

    function commit(entry: var): void {
        // Hidden afresh from now, so the grace before a poll trusts Gmail
        // again runs from the request rather than from the click.
        if (root.opened[entry.row.id]) {
            const mark = Object.assign({}, root.opened);
            mark[entry.row.id] = Date.now();
            root.opened = mark;
        }
        root.perform(entry.kind, entry.row);
        if (entry.also)
            entry.also(entry.row);
    }

    // The request behind each verb. Archive here means done: out of the
    // inbox and read, so it cannot come back to a count anywhere. Gmail
    // stars a message rather than a thread, so a star goes on the newest
    // one and coming off it comes off them all. Needs the gmail.modify
    // scope; a token granted before it was added gets a 403, and a dropped
    // row returns after the grace period, with `trouble` saying why. A label
    // change lands the same however often it is sent, so one that stalls
    // goes again over the fallback the way reads do.
    function perform(kind: string, row: var): void {
        const thread = `${root.api}/threads/${row.id}/modify`;
        const [url, labels] = {
            archive: [thread, { removeLabelIds: ["INBOX", "UNREAD"] }],
            read: [thread, { removeLabelIds: ["UNREAD"] }],
            star: [`${root.api}/messages/${row.last || row.message}/modify`, { addLabelIds: ["STARRED"] }],
            unstar: [thread, { removeLabelIds: ["STARRED"] }]
        }[kind] ?? [];
        if (url)
            root.send("POST", url, labels, function () {}, null, true);
    }

    // A row's star turned here, in its list and in the cache, so a poll
    // before the request lands does not turn it back.
    function restar(id: string, starred: bool): void {
        const turn = r => r.id === id ? Object.assign({}, r, { starred: starred }) : r;
        root.threads = root.threads.map(turn);
        root.otherThreads = root.otherThreads.map(turn);
        if (root.cache[id])
            root.cache[id] = Object.assign({}, root.cache[id], { row: turn(root.cache[id].row) });
        root.snapshot = "";
    }

    // An undone row back where it was: in its list by date, counted again,
    // and no longer hidden from the polls.
    function restore(entry: var): void {
        const row = entry.row;
        const mark = Object.assign({}, root.opened);
        delete mark[row.id];
        root.opened = mark;
        if (!root[entry.list].some(t => t.id === row.id))
            root[entry.list] = root[entry.list].concat([row]).sort((a, b) => b.at - a.at);
        if (entry.list === "otherThreads")
            root.other += 1;
        else
            root.total += 1;
        if (root.found)
            root.found = Object.assign({}, root.found, {
                rows: root.found.rows.map(r => r.id === row.id ? Object.assign({}, r, { unread: row.unread }) : r)
            });
        root.snapshot = "";
        root.restored(row, entry.wasOpen);
    }

    // Remove immediately and guard against replies from the current poll.
    // Polls wait briefly for Gmail to confirm the read (see `opened`).
    function drop(thread: var): void {
        // Once: a mail read in the launcher and then opened in Gmail would
        // otherwise come off the count twice.
        if (root.opened[thread.id])
            return;
        // A search that turned it up says so too, or going back to it from
        // the launcher's reader would show it still unread.
        if (root.found)
            root.found = Object.assign({}, root.found, {
                rows: root.found.rows.map(r => r.id === thread.id ? Object.assign({}, r, {
                        unread: false
                    }) : r)
            });
        const mark = Object.assign({}, root.opened);
        mark[thread.id] = Date.now();
        root.opened = mark;
        // Dealt with here, so its card has nothing left to ask.
        Notifications.withdraw("x-gmail-thread", thread.id);
        // Off the count it was in, which the rows alone cannot say: an Other
        // mail read before that row was unfolded has no row yet, and an
        // archived one a search found was never counted at all.
        const inOther = root.otherThreads.some(t => t.id === thread.id);
        const inMain = root.threads.some(t => t.id === thread.id);
        const list = root.counted[thread.id] ?? (inOther ? "other" : inMain ? "total" : "");
        if (inOther)
            root.otherThreads = root.otherThreads.filter(t => t.id !== thread.id);
        if (inMain)
            root.threads = root.threads.filter(t => t.id !== thread.id);
        if (list === "other")
            root.other = Math.max(0, root.other - 1);
        else if (list === "total")
            root.total = Math.max(0, root.total - 1);
        root.snapshot = "";
    }

    function openInbox(): void {
        Quickshell.execDetached(Settings.webApp("gmail", "", root.web));
    }

    // A new mail, in its own Gmail window, with the subject filled in
    // when there is one (the launcher's ctrl+enter).
    function compose(subject: string): void {
        const su = subject ? `&su=${encodeURIComponent(subject)}` : "";
        Quickshell.execDetached(Settings.webApp("gmail", `${root.web}?view=cm&fs=1${su}`, root.web));
    }

    Component {
        id: card

        Process {
            id: waiting

            property var row
            property string code

            stdout: StdioCollector {
                id: chosen
            }
            onExited: {
                root.answered(chosen.text.trim(), waiting.row, waiting.code);
                waiting.destroy();
            }
        }
    }

    Component {
        id: saver

        Process {
            id: download

            property var part
            property var done
            property var landed

            stdout: StdioCollector {
                id: saved
            }
            stderr: StdioCollector {
                id: why
            }
            onExited: code => {
                download.done();
                if (code !== 0)
                    root.trouble = `Could not save ${download.part.name}: ${why.text.trim().split("\n").pop() || "the download failed"}`;
                download.landed(code === 0 ? saved.text.trim() : "");
                download.destroy();
            }
        }
    }

    // qs ipc call email …
    IpcHandler {
        target: "email"

        function refresh(): void {
            root.refresh();
        }

        function list(): string {
            if (root.trouble !== "")
                return root.trouble;
            if (!root.loaded)
                return root.tooltip;
            const out = root.threads.map(t => `${root.sayWhen(t.at)}  ${t.from}  ·  ${t.subject}`);
            return out.length > 0 ? `${root.total} unread\n${out.join("\n")}` : "No unread mail";
        }
    }
}

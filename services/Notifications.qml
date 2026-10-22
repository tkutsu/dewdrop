pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import qs

// The desktop's notification server. It was swaync until 2026-09-26; the shell
// owns org.freedesktop.Notifications itself now, so the notification that
// arrives, the notice beside the clock, the bell and the centre are all one
// thing rather than a daemon and a bar reading it from outside.
//
// What it does, in the order a notification meets it: decides whether it is
// kept (the transient rules below), whether it replaces one already there,
// shows it as it arrives, and decides for how long.
Singleton {
    id: root

    // Every notification being kept, newest first: by when it arrived or was
    // last updated, since an update in place keeps its slot in the server's
    // own order. One not stamped yet is arriving now. `arrived` is mutated
    // in place, so `stamps` is what says it changed.
    readonly property var list: {
        root.stamps;
        const at = n => root.arrived[n.id] ?? Number.MAX_SAFE_INTEGER;
        return [...server.trackedNotifications.values].reverse().sort((a, b) => at(b) - at(a));
    }
    property int stamps: 0
    readonly property int count: list.length

    readonly property string icon: Theme.glyph.notif

    // What the bell counts: everything kept but the one on show beside the
    // clock, which is being read right now. It joins the count as its notice
    // folds, and a fleeting one, gone by then, never does.
    readonly property int waiting: count - (showing && latest && list.includes(latest) ? 1 : 0)

    // Hidden at 0, held at 99.
    readonly property string label: waiting === 0 ? "" : String(Math.min(waiting, 99))

    readonly property string tooltip: count === 0 ? "No notifications" : count === 1 ? "1 notification" : `${count} notifications`

    // --- the notice beside the clock ----------------------------------------
    // The one on show, and whether it still is. The object goes null by itself
    // if the notification is closed while it is up.
    property Notification latest: null
    property bool showing: false
    // The pointer is on it, which holds it open: a notice that folded away
    // under the pointer that was reaching for it would be read as a misclick.
    property bool held: false

    // How many more arrived while the notice was already up, for the "+3" at
    // its end: a burst, not the centre's total. The total is almost never
    // news, and a notice that said "+22" every time would soon go unread.
    // Behind an urgent notice it is how many are waiting for their turn.
    property int burst: 0

    // An urgent notice stays until it is answered, so what arrives meanwhile
    // waits behind it rather than taking its place, oldest first.
    readonly property bool urgent: root.showing && root.latest?.urgency === NotificationUrgency.Critical
    property var queued: []

    // Done with the notice on show. Given the one that was clicked, and only
    // if it is still the one on show: a click that ran its action has
    // already moved on to the next.
    function dismissNotice(n) {
        if (n && n !== root.latest)
            return;
        if (root.queued.length > 0)
            root.advance();
        else
            root.showing = false;
    }

    // The next turn after an urgent notice: the next urgent one if any is
    // waiting, else the newest of the rest with a count of the others, timed
    // as usual. Those others are in the centre; one notice each would keep
    // the pill busy for minutes after a burst.
    function advance() {
        const waiting = root.queued.filter(q => q && root.list.includes(q));
        const next = waiting.find(q => q.urgency === NotificationUrgency.Critical) ?? waiting[waiting.length - 1];
        if (!next) {
            root.queued = [];
            root.showing = false;
            return;
        }
        const previous = root.latest;
        const rest = waiting.filter(q => q !== next);
        root.queued = next.urgency === NotificationUrgency.Critical ? rest : [];
        root.burst = rest.length;
        root.latest = next;
        root.showing = true;
        root.timeNotice();
        if (previous && previous !== next)
            root.letGo(previous);
    }

    // --- the centre -----------------------------------------------------------
    // The centre is the bell's popup, and the bell is a bar item with one
    // copy per screen, so asking for it is a request the bell on the focused
    // screen answers (NotificationBell) rather than a window opened from here.
    // `toggle` for the IPC's toggle; otherwise it opens, or stays open.
    signal centreRequested(bool toggle)

    // The notification the centre opens on: picked from the notice beside the
    // clock, so the centre scrolls to it and marks it rather than opening at
    // the top as if nothing had been asked for. Cleared as the popup closes.
    property Notification centreFocus: null

    // Opening a notice in the centre. Also what keeps it there: a fleeting
    // one would otherwise be let go as its notice folds, which is the moment
    // it is being asked for — the centre opened on an empty space where it
    // had just been.
    function focusOn(n) {
        if (!n)
            return;
        delete root.passing[n.id];
        root.centreFocus = n;
        root.centreRequested(false);
    }

    function toggleCentre() {
        root.centreRequested(true);
    }

    function clearAll() {
        for (const n of root.list)
            n.dismiss();
    }

    // Clicking a notification is asking for what it is about: its default
    // action when it has one, else the app that sent it. Either way it has
    // been dealt with, so it goes.
    function activate(n) {
        const open = n.actions.find(a => a.identifier === "default");
        if (open)
            return root.run(open, n);
        OpenPopup.dismiss();
        root.focusSender(n);
        n.dismiss();
    }

    // An action taken here clears its notification, resident or not: the
    // click is the answer, and a card left behind would ask again. Quickshell
    // already closes a non-resident one as it invokes, so only a resident one
    // is still in the list by then.
    function run(action, n) {
        OpenPopup.dismiss();
        action.invoke();
        if (n && root.list.includes(n))
            n.dismiss();
    }

    // Take back the cards whose `hint` says `value`: a mail dealt with in the
    // shell has nothing left to ask about.
    function withdraw(hint: string, value: string): void {
        for (const n of root.list)
            if (n.hints?.[hint] === value)
                n.dismiss();
    }

    // The sender's most recently used window, or the app itself when it
    // named its desktop entry and has no window open. A sender that is
    // neither (notify-send, a script) has nowhere to go.
    function focusSender(n) {
        const entry = n.desktopEntry ? DesktopEntries.byId(n.desktopEntry) : null;
        const names = [n.desktopEntry, entry?.startupClass, n.appName].filter(s => s).map(s => s.toLowerCase());
        const windows = Hyprland.toplevels.values.filter(t => names.includes((t.wayland?.appId || t.lastIpcObject?.class || "").toLowerCase()));
        const recent = windows.sort((a, b) => (a.lastIpcObject?.focusHistoryID ?? 1e9) - (b.lastIpcObject?.focusHistoryID ?? 1e9))[0];
        if (recent)
            Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${recent.address}" })`);
        else
            entry?.execute();
    }

    // The actions worth a button: everything but the default one, which is
    // what clicking the notification itself does.
    function buttons(n) {
        return n ? n.actions.filter(a => a.identifier !== "default") : [];
    }

    // --- presentation helpers -------------------------------------------------
    // Inline Markdown and notification HTML become StyledText, which keeps
    // the cards' wrapping and ellipsis. Protect code and tags from Markdown
    // replacements, and escape comparison signs in ordinary text.
    function styled(s) {
        const tokens = [];
        const keep = value => "\u0001" + (tokens.push(value) - 1) + "\u0002";
        const escape = value => value.replace(/&(?!(?:amp|lt|gt|quot|apos|nbsp|#\d+|#x[\da-f]+);)/gi, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
        let text = String(s ?? "").replace(/(`+)([^`]*?)\1/g, (_, ticks, code) => keep("<font face=\"monospace\">" + escape(code) + "</font>"));
        // Breaks and paragraphs become newlines, so "<p>a</p><p>b</p>" or a
        // trailing newline does not open the card on (or end it with) a blank line.
        text = text.replace(/<\/?(?:b|strong|i|em|u|s|del|a|br|p|span|img)\b[^>]*>/gi, tag => {
            if (/^<\/?(?:span|img)\b/i.test(tag))
                return "";
            if (/^<\/?(?:br|p)\b/i.test(tag))
                return "\n";
            return keep(tag.replace(/<(\/?)(strong|em|del)\b/gi, (_, close, name) => "<" + close + ({strong: "b", em: "i", del: "s"})[name.toLowerCase()]));
        });
        text = escape(text.trim().replace(/\n{3,}/g, "\n\n"));
        text = text.replace(/\[([^\]\n]+)\]\(([^\s)]+)\)/g, (_, label, url) => keep("<a href=\"" + url + "\">") + label + keep("</a>"));
        // Emphasis needs text hugging its markers, as in Markdown, so "2 * 3 * 4" stays arithmetic.
        text = text.replace(/\*\*(?=\S)([^\n]*?\S)\*\*/g, "<b>$1</b>").replace(/(^|\W)__(?=\S)([^\n]*?\S)__(?=$|\W)/g, "$1<b>$2</b>");
        text = text.replace(/~~(?=\S)([^\n]*?\S)~~/g, "<s>$1</s>");
        text = text.replace(/(^|[^*\w])\*(?=[^\s*])([^*\n]*?[^\s*])\*(?![*\w])/g, "$1<i>$2</i>").replace(/(^|\W)_(?=\S)([^_\n]*?\S)_(?=$|\W)/g, "$1<i>$2</i>");
        text = text.replace(/\n/g, "<br>");
        return text.replace(/\u0001(\d+)\u0002/g, (token, index) => tokens[Number(index)] ?? token);
    }

    // The bar has one line: use the same markup interpretation, then flatten it.
    // Numeric entities too: senders that escape for markup send "it&#39;s".
    function plain(s) {
        const character = (_, code) => {
            const point = /^x/i.test(code) ? parseInt(code.slice(1), 16) : Number(code);
            return point > 0 && point <= 0x10ffff ? String.fromCodePoint(point) : _;
        };
        return root.styled(s).replace(/<br>/gi, " ").replace(/<\/?(?:b|i|u|s|a|font)\b[^>]*>/gi, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&apos;/g, "'").replace(/&nbsp;/g, " ").replace(/&#(x[\da-f]+|\d+);/gi, character).replace(/&amp;/g, "&").replace(/\s+/g, " ").trim();
    }

    // Links in a card open in the browser; anything else (javascript:, file:)
    // is not something a notification gets to launch.
    function openLink(url) {
        if (/^(?:https?|mailto):/i.test(url))
            Qt.openUrlExternally(url);
    }

    // What AppIcon should look the sender up as: its desktop entry if it named
    // one, then its icon if that is a theme name rather than a file, then
    // whatever it calls itself.
    function keyOf(n) {
        if (!n)
            return "";
        const icon = n.appIcon ?? "";
        return n.desktopEntry || (icon && !icon.includes("/") ? icon : "") || n.appName;
    }

    // A file or image URL for a path, which senders send as either. An
    // image-path sent as a bare path reaches us as an icon request for it
    // (image://icon//tmp/shot.png), which is a picture, not a theme icon.
    function url(s) {
        s = s ?? "";
        if (s.startsWith("image://icon//"))
            s = s.slice("image://icon/".length);
        return s.startsWith("/") ? "file://" + s : s;
    }

    // The icon the sender sent as a picture (a path or URL) rather than a
    // theme name, which no lookup by name would find.
    function pictureOf(n) {
        const icon = n?.appIcon ?? "";
        return icon.includes("/") || icon.includes(":") ? root.url(icon) : "";
    }

    // The sender's icon as something an Image can load: the icon it sent —
    // a picture or a theme name — else its desktop entry's, else nothing, and
    // the card draws a mark of its own.
    function iconFor(n) {
        if (!n)
            return "";
        const picture = root.pictureOf(n);
        if (picture)
            return picture;
        DesktopEntries.applications.values.length;
        const name = n.appIcon || DesktopEntries.heuristicLookup(n.desktopEntry || n.appName)?.icon || "";
        return name ? Quickshell.iconPath(name, true) : "";
    }

    // "now", "4m", "2h", then the weekday — the way the system's own centre
    // says it, short enough to sit on the same line as the app's name.
    function ago(n, now) {
        root.remember(n);
        const at = root.arrived[n.id];
        const s = Math.max(0, (now - at) / 1000);
        if (s < 60)
            return "now";
        if (s < 3600)
            return `${Math.floor(s / 60)}m`;
        if (s < 86400)
            return `${Math.floor(s / 3600)}h`;
        return Qt.locale().dayName(new Date(at).getDay(), Locale.ShortFormat);
    }

    // When each one came in, by id. The server does not record it.
    //
    // Mutated in place and pruned when the notification closes, never
    // replaced: replacing the object would re-run every card's age on every
    // arrival. A hot reload starts a new engine, which cannot read the old
    // one's objects, so a JSON copy carries the times across and is merged in
    // once, the restored stamps winning over any taken while it loaded.
    readonly property var arrived: ({})
    PersistentProperties {
        id: retained
        reloadableId: "notification-arrivals"
        property string arrivalsJson: "{}"
        onLoaded: {
            Object.assign(root.arrived, JSON.parse(retained.arrivalsJson));
            root.stamps++;
        }
    }

    // --- arrival ------------------------------------------------------------
    // Summary rules for notices that only matter at arrival. App-name rules
    // live in Settings.ephemeralNotificationApps so they can be edited.
    //
    // Claude Code names itself in the summary through whichever terminal it
    // runs in; inside herdr it is herdr that speaks (`notify-send --app-name
    // Herdr`), for its own agents' turns as much as for Claude's.
    readonly property var fleeting: [
        {
            summary: /Claude Code/
        },
        {
            summary: /hyprwhspr/
        }
    ]

    function isFleeting(n) {
        if (n.transient)
            return true;
        const app = (n.appName ?? "").toLowerCase();
        return Settings.ephemeralNotificationApps.some(name => name.toLowerCase() === app)
            || root.fleeting.some(r => r.summary.test(n.summary));
    }

    // The ids that go as soon as their notice has been seen. Only ever read
    // from functions, so it is mutated in place like `arrived`.
    readonly property var passing: ({})
    readonly property var observed: ({})

    // Restore metadata for notices kept by the server through hot reload.
    function remember(n) {
        if (root.arrived[n.id] === undefined)
            root.arrived[n.id] = Date.now();
        if (root.observed[n.id] === n)
            return;
        root.observed[n.id] = n;
        retained.arrivalsJson = JSON.stringify(root.arrived);
        // A sender updating one in place (replaces_id: progress, a changed
        // song) changes this object rather than sending a new one, and
        // Quickshell says nothing else about it. It is news again: shown, timed
        // afresh, and as old as the update.
        const updated = () => {
            root.arrived[n.id] = Date.now();
            retained.arrivalsJson = JSON.stringify(root.arrived);
            root.stamps++;
            root.announce(n);
        };
        n.summaryChanged.connect(updated);
        n.bodyChanged.connect(updated);
        n.closed.connect(() => {
            delete root.arrived[n.id];
            delete root.passing[n.id];
            delete root.observed[n.id];
            retained.arrivalsJson = JSON.stringify(root.arrived);
            // Withdrawn by its sender, or cleared in the centre: it no longer
            // waits its turn, and if it was on show, the next one has it.
            if (root.queued.includes(n)) {
                root.queued = root.queued.filter(q => q !== n);
                root.burst = root.queued.length;
            }
            if (n === root.latest && root.showing)
                root.dismissNotice();
        });
    }

    function receive(n) {
        // Kept by default; a fleeting one is kept too, just for as long as its
        // notice is up, since an untracked notification is closed the moment
        // this handler returns.
        n.tracked = true;
        root.remember(n);
        // A hot reload hands every kept notification back through here, after
        // the new generation is built. They were seen in the last one, so they
        // go back in the list without a notice; a fleeting one was only ever
        // the notice, so it goes.
        if (n.lastGeneration) {
            if (root.isFleeting(n))
                n.expire();
            return;
        }
        if (root.isFleeting(n))
            root.passing[n.id] = true;
        root.announce(n);
    }

    // Show the arriving notification on the bar beside the clock.
    function announce(n) {
        // A sender that tags its notifications (the volume and mic toasts do,
        // with x-canonical-private-synchronous) means each one to replace the
        // last, not to pile up behind it.
        const tag = n.hints?.["x-canonical-private-synchronous"];
        // Replacing the one on show is not one more on top of it.
        const replacing = !!tag && root.showing && root.latest?.hints?.["x-canonical-private-synchronous"] === tag;
        if (tag) {
            for (const other of root.list)
                if (other !== n && other.hints?.["x-canonical-private-synchronous"] === tag)
                    other.dismiss();
        }

        // Behind an urgent notice, what arrives waits its turn. What is only
        // for the moment (a fleeting one, a volume toast) has had its moment
        // by then, so it is let go instead.
        if (root.urgent && root.latest !== n && !replacing) {
            if (tag || root.passing[n.id])
                root.letGo(n);
            else if (!root.queued.includes(n)) {
                root.queued = [...root.queued, n];
                root.burst = root.queued.length;
            }
            return;
        }

        // The notice it replaces was only waiting on its time.
        if (root.latest && root.latest !== n)
            root.letGo(root.latest);
        // Nor is an update to the one on show. An urgent one counts only what
        // waits behind it, so it starts at none.
        if (n.urgency === NotificationUrgency.Critical && root.latest !== n)
            root.burst = 0;
        else if (root.showing && !replacing && root.latest !== n)
            root.burst++;
        root.latest = n;
        root.showing = true;
        root.timeNotice();
    }

    // Done with as a notice. A fleeting one is done with altogether.
    function letGo(n) {
        if (n && root.passing[n.id]) {
            delete root.passing[n.id];
            n.expire();
        }
    }

    onShowingChanged: if (!showing) {
        root.queued = [];
        root.burst = 0;
        root.letGo(root.latest);
    }

    // How long a notice stays up. A critical one until it is answered,
    // whatever its sender asked for. Otherwise the sender's own timeout when
    // it gave one, else by urgency, the way swaync was set up to time its
    // popups: low goes quickly. expireTimeout is documented in seconds but
    // holds the D-Bus value, which is milliseconds.
    readonly property int noticeMs: {
        const n = root.latest;
        if (!n || n.urgency === NotificationUrgency.Critical)
            return 0;
        // 0 is the sender saying never; -1 leaves it to us.
        if (n.expireTimeout >= 0)
            return n.expireTimeout;
        return n.urgency === NotificationUrgency.Low ? 3000 : 6000;
    }

    Timer {
        id: noticeTimer
        interval: Math.max(1, root.noticeMs)
        running: root.showing && !root.held && root.noticeMs > 0
        onTriggered: root.showing = false
    }

    // restart() starts even a stopped timer, so enforce the hold and timeout.
    function timeNotice(): void {
        if (root.showing && !root.held && root.noticeMs > 0)
            noticeTimer.restart();
        else
            noticeTimer.stop();
    }

    // A notice whose notification was closed from elsewhere — the sender
    // withdrew it, or it was cleared in the centre — has nothing left to show,
    // and hands over to the next one waiting.
    onLatestChanged: if (!latest)
        root.dismissNotice()

    NotificationServer {
        id: server

        // Survive a hot reload with everything still held.
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: n => root.receive(n)
    }

    //   qs ipc call notifications toggle | clear | latest
    IpcHandler {
        target: "notifications"

        function toggle(): void {
            root.toggleCentre();
        }

        function clear(): void {
            root.clearAll();
        }

        // The centre, opened on the newest notification — what clicking the
        // notice beside the clock does, for a keybind.
        function latest(): void {
            root.focusOn(root.list[0] ?? null);
        }
    }
}

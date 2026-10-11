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
// whether it is shown as it arrives (do-not-disturb), and for how long.
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

    // Do not disturb: kept, counted, listed in the centre, never shown as they
    // arrive — except a critical one, which is the sender saying it cannot
    // wait. Remembered across restarts (see `state`).
    property bool dnd: false

    function setDnd(on) {
        root.dnd = on;
        stored.dnd = on;
        state.writeAdapter();
    }

    readonly property string icon: dnd ? Theme.glyph.notifDnd : Theme.glyph.notif

    // What the bell counts: everything kept but the one on show beside the
    // clock, which is being read right now. It joins the count as its notice
    // folds, and a fleeting one, gone by then, never does.
    readonly property int waiting: count - (showing && latest && list.includes(latest) ? 1 : 0)

    // Hidden at 0, held at 99.
    readonly property string label: waiting === 0 ? "" : String(Math.min(waiting, 99))

    readonly property string tooltip: {
        const n = count === 0 ? "No notifications" : count === 1 ? "1 notification" : `${count} notifications`;
        return n + (dnd ? "  ·  Do Not Disturb" : "");
    }

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
    property int burst: 0

    function dismissNotice() {
        root.showing = false;
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
    // Senders that only ever have something to say in the moment: shown as
    // they arrive and then gone, never kept in the centre. Carried over from
    // swaync's notification-visibility rules, where these were "transient".
    //
    // Claude Code names itself in the summary through whichever terminal it
    // runs in; inside herdr it is herdr that speaks (`notify-send --app-name
    // Herdr`), for its own agents' turns as much as for Claude's.
    readonly property var fleeting: [
        {
            summary: /Claude Code/
        },
        {
            app: /^Herdr$/
        },
        {
            app: /^Email$/
        },
        {
            summary: /hyprwhspr/
        },
        {
            app: /^satty$/
        },
        {
            app: /^qBittorrent$/
        },
        {
            app: /^udiskie$/
        }
    ]

    function isFleeting(n) {
        if (n.transient)
            return true;
        return root.fleeting.some(r => (!r.app || r.app.test(n.appName)) && (!r.summary || r.summary.test(n.summary)));
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

    // On the bar beside the clock, unless do-not-disturb holds it back.
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

        if (root.dnd && n.urgency !== NotificationUrgency.Critical) {
            root.letGo(n);
            return;
        }
        // The notice it replaces was only waiting on its time.
        if (root.latest && root.latest !== n)
            root.letGo(root.latest);
        // Nor is an update to the one on show.
        if (root.showing && !replacing && root.latest !== n)
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
        root.letGo(root.latest);
        root.burst = 0;
    }

    // How long a notice stays up. The sender's own timeout when it gave one;
    // otherwise by urgency, the way swaync was set up to time its popups —
    // low goes quickly, critical waits to be answered. expireTimeout is
    // documented in seconds but holds the D-Bus value, which is milliseconds.
    readonly property int noticeMs: {
        const n = root.latest;
        if (!n)
            return 0;
        // 0 is the sender saying never; -1 leaves it to us.
        if (n.expireTimeout >= 0)
            return n.expireTimeout;
        return n.urgency === NotificationUrgency.Low ? 3000 : n.urgency === NotificationUrgency.Critical ? 0 : 6000;
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

    // Let go of by the pointer, a notice gets its full time again rather than
    // whatever was left when it was reached for.
    onHeldChanged: root.timeNotice()

    // A notice whose notification was closed from elsewhere — the sender
    // withdrew it, or it was cleared in the centre — has nothing left to show.
    onLatestChanged: if (!latest)
        root.showing = false

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

    FileView {
        id: state

        path: Paths.state("notifications.json")
        printErrors: false
        onLoaded: root.dnd = stored.dnd
        onLoadFailed: state.writeAdapter()

        JsonAdapter {
            id: stored

            property bool dnd: false
        }
    }

    //   qs ipc call notifications toggle | clear | dnd | latest
    IpcHandler {
        target: "notifications"

        function toggle(): void {
            root.toggleCentre();
        }

        function clear(): void {
            root.clearAll();
        }

        function dnd(): void {
            root.setDnd(!root.dnd);
        }

        // The centre, opened on the newest notification — what clicking the
        // notice beside the clock does, for a keybind.
        function latest(): void {
            root.focusOn(root.list[0] ?? null);
        }
    }
}

pragma Singleton

import QtQuick
import Quickshell
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

    // Every notification being kept, newest first.
    readonly property var list: [...server.trackedNotifications.values].reverse()
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

    // Hidden at 0, held at 99.
    readonly property string label: count === 0 ? "" : String(Math.min(count, 99))

    readonly property string tooltip: {
        const n = count === 0 ? "No notifications" : count === 1 ? "1 notification" : `${count} notifications`;
        return n + (dnd ? "  ·  do not disturb" : "");
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
    property bool centreShown: false
    // Outlives `centreShown` by the length of the centre's slide out.
    readonly property bool centreActive: linger.active

    Linger {
        id: linger
        shown: root.centreShown
    }

    // An action picked in the centre, run once it has gone (see run).
    property NotificationAction afterCentre: null

    onCentreActiveChanged: if (!centreActive && afterCentre) {
        root.afterCentre.invoke();
        root.afterCentre = null;
    }

    // The notification the centre opens on: picked from the notice beside the
    // clock, so the centre scrolls to it and marks it rather than opening at
    // the top as if nothing had been asked for.
    property Notification centreFocus: null

    onCentreShownChanged: if (!centreShown)
        root.centreFocus = null

    // Opening a notice in the centre. Also what keeps it there: a fleeting
    // one would otherwise be let go as its notice folds, which is the moment
    // it is being asked for — the centre opened on an empty space where it
    // had just been.
    function focusOn(n) {
        if (!n)
            return;
        delete root.passing[n.id];
        root.centreFocus = n;
        root.centreShown = true;
    }

    function toggleCentre() {
        root.centreShown = !root.centreShown;
    }

    function clearAll() {
        for (const n of root.list)
            n.dismiss();
    }

    // Clicking a notification is asking for what it is about: its default
    // action when it has one. Either way it has been dealt with, so it goes.
    function activate(n) {
        const open = n.actions.find(a => a.identifier === "default");
        if (open)
            root.run(open);
        else if (!n.resident)
            n.dismiss();
    }

    // An action picked in the centre waits for the centre to fold away: while
    // it holds the keyboard, Hyprland refuses focus to the window the action
    // raises, and letting go only reaches Hyprland with a later frame than the
    // sender's request for focus.
    function run(action) {
        if (root.centreActive) {
            root.afterCentre = action;
            root.centreShown = false;
        } else
            action.invoke();
    }

    // The actions worth a button: everything but the default one, which is
    // what clicking the notification itself does.
    function buttons(n) {
        return n ? n.actions.filter(a => a.identifier !== "default") : [];
    }

    // --- presentation helpers -------------------------------------------------
    // Markup is not advertised (bodyMarkupSupported), but some senders send it
    // anyway; a line of text has no use for any of it.
    function plain(s) {
        return String(s ?? "").replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&apos;/g, "'").replace(/&amp;/g, "&").replace(/\s+/g, " ").trim();
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

    // A file or image URL for a path, which senders send as either.
    function url(s) {
        s = s ?? "";
        return s.startsWith("/") ? "file://" + s : s;
    }

    // The sender's icon as something an Image can load: the icon it sent —
    // a path or a theme name — else its desktop entry's, else nothing, and
    // the card draws a mark of its own.
    function iconFor(n) {
        if (!n)
            return "";
        const icon = n.appIcon ?? "";
        if (icon.includes("/") || icon.includes(":"))
            return root.url(icon);
        DesktopEntries.applications.values.length;
        const name = icon || DesktopEntries.heuristicLookup(n.desktopEntry || n.appName)?.icon || "";
        return name ? Quickshell.iconPath(name, true) : "";
    }

    // "now", "4m", "2h", then the weekday — the way the system's own centre
    // says it, short enough to sit on the same line as the app's name.
    function ago(n, now) {
        const at = root.arrived[n.id] ?? now;
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
    // replaced: an arrival time is written before any card exists to read it
    // and never changes afterwards, so there is nothing for a change signal to
    // tell anyone — and replacing the object made every card's age re-run on
    // every arrival, while never pruning grew it for the life of the session.
    readonly property var arrived: ({})

    // --- arrival ------------------------------------------------------------
    // Senders that only ever have something to say in the moment: shown as
    // they arrive and then gone, never kept in the centre. Carried over from
    // swaync's notification-visibility rules, where these were "transient".
    readonly property var fleeting: [
        {
            app: /^kitty$/,
            summary: /Claude Code/
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

    function receive(n) {
        // Kept by default; a fleeting one is kept too, just for as long as its
        // notice is up, since an untracked notification is closed the moment
        // this handler returns.
        n.tracked = true;
        root.arrived[n.id] = Date.now();
        n.closed.connect(() => {
            delete root.arrived[n.id];
            delete root.passing[n.id];
        });
        if (root.isFleeting(n))
            root.passing[n.id] = true;

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
        if (root.showing && !replacing)
            root.burst++;
        root.latest = n;
        root.showing = true;
        noticeTimer.restart();
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
    // low goes quickly, critical waits to be answered.
    readonly property int noticeMs: {
        const n = root.latest;
        if (!n)
            return 0;
        if (n.expireTimeout > 0)
            return n.expireTimeout * 1000;
        return n.urgency === NotificationUrgency.Low ? 3000 : n.urgency === NotificationUrgency.Critical ? 0 : 6000;
    }

    Timer {
        id: noticeTimer
        interval: Math.max(1, root.noticeMs)
        running: root.showing && !root.held && root.noticeMs > 0
        onTriggered: root.showing = false
    }

    // Let go of by the pointer, a notice gets its full time again rather than
    // whatever was left when it was reached for.
    onHeldChanged: if (!held && showing)
        noticeTimer.restart()

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

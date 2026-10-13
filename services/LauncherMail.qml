pragma Singleton
import QtQuick
import Quickshell
import qs

// Mail search, inline reading and activation for the launcher.
Singleton {
    id: root
    // --- mail ----------------------------------------------------------------

    // "@" on its own is the unread the bar already has, so it is on screen at
    // once. Anything past it is a Gmail search, which is a round trip to
    // Google — debounced harder than the disk walk for it, and shown only
    // once the answer for this exact query is back (see Email.found).
    function results(query) {
        const note = title => [Launcher.noteRow(Theme.glyph.mailRead, title)];
        if (!Email.configured)
            return note(`Gmail not connected — run ${Google.setup}`);

        // Reading one: its row alone, as the header over its text, which the
        // box draws under the list (see LauncherMenu's reader).
        if (root.open)
            return [root.row(root.open)];

        if (!query) {
            if (!Email.loaded)
                return note(Email.trouble || "reading mail…");
            if (Email.threads.length)
                return Email.threads.map(root.row);
            // Nothing unread: the inbox, newest first, which route() has
            // already asked for. The note stands in until it lands.
            const recent = Email.found;
            if (Email.trouble)
                return note(Email.trouble);
            if (Email.loading && !recent?.rows.length)
                return note("reading inbox...");
            if (!recent || recent.q !== root.recentMail)
                return note("reading inbox...");
            if (recent.trouble)
                return note(recent.trouble);
            if (!recent.rows.length)
                return note("no unread mail");
            return recent.rows.map(root.row);
        }

        const found = Email.found;
        if (!found || found.q !== query)
            return note("searching…");
        if (found.trouble)
            return note(found.trouble);
        return found.rows.length ? found.rows.map(root.row) : note("no mail matches");
    }

    // The thread Tab opened to read, or null. The thread itself rather than
    // its id: reading marks it read, which takes it off the unread list this
    // would otherwise have to find it in.
    property var open: null
    // Its text, "" until it lands.
    readonly property string text: !root.open ? "" : (root.open.messages ?? []).map(message => {
        const body = Email.bodies[message.id] ?? message.snippet ?? "";
        return `${message.from}  ${Email.sayWhen(message.at)}\n${body}`;
    }).join("\n\n")

    // Tab in mail mode: read the selected mail, or go back to the list from
    // one, onto the row it was read from if it is still there. Reading counts
    // as read, the way opening it in Gmail does.
    function fold(): void {
        const open = root.open;
        if (open) {
            root.open = null;
            Launcher.index = Math.max(0, Launcher.results.findIndex(x => x.kind === "mail" && x.thread.id === open.id));
            return;
        }
        const r = Launcher.selected;
        if (!r || r.kind !== "mail")
            return;
        Email.read(r.thread);
        if (r.thread.unread)
            Email.markRead(r.thread);
        root.open = Object.assign({}, r.thread, {
            unread: false
        });
        Launcher.index = 0;
    }

    // Subject first, since it is what the mail is; who and when to the right.
    // A read thread sits a shade back; a starred one wears the star, which is
    // what put it at the top of a search.
    function row(t) {
        return {
            kind: "mail",
            thread: t,
            glyph: t.starred ? Theme.glyph.mailStarred : t.unread ? Theme.glyph.mailUnread : Theme.glyph.mailRead,
            title: t.subject,
            subtitle: [t.from, Email.sayWhen(t.at)].filter(x => x).join("  ·  "),
            raw: true,
            dim: !t.unread
        };
    }

    Timer {
        id: mailSearch

        property string want: ""

        interval: 300
        onTriggered: Email.search(mailSearch.want, true)
    }

    // What a bare "@" lists when nothing is unread.
    readonly property string recentMail: "in:inbox"

    // A changed query closes whatever was being read. A bare "@" with nothing
    // unread lists the inbox instead, asked at once rather than after the
    // debounce: nothing was typed to wait out.
    function route(inMode, text): void {
        root.open = null;
        if (inMode && !text && !Email.threads.length && !(Email.found?.q === root.recentMail && !Email.found.trouble && Date.now() - Email.found.at < 30000))
            Email.search(root.recentMail, false);
        const want = inMode ? text : "";
        if (want !== mailSearch.want) {
            mailSearch.want = want;
            if (want)
                mailSearch.restart();
            else
                mailSearch.stop();
        }
    }

    function cancel(): void {
        mailSearch.stop();
        mailSearch.want = "";
    }

    // Ctrl+Enter writes a new one, whatever row is selected and whether or
    // not there is one: what was typed is the subject.
    function activate(row, mode): bool {
        if (mode === "play") {
            Email.compose(Launcher.classification.text);
            return true;
        }
        if (row?.kind !== "mail")
            return false;
        Email.open(row.thread);
        return true;
    }
}

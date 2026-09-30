pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import qs
import qs.components

// MPD state, straight off the MPD protocol.
//
// mpd publishes no MPRIS, so Services.Mpris cannot see it and the waybar module
// polled every 5 seconds instead. MPD's own `idle` command pushes changes as
// they happen, so this sits silent until something actually moves.
//
// Two connections, both components/MpdLink.qml: one parked in `idle` that
// everything is read over, and one that never idles that everything is sent
// over. Sending on the idling one would mean a noidle handshake unwound
// around every reply; a second socket has none of that problem.
Singleton {
    id: root

    property string state: "stop"
    property string title: ""
    property string artist: ""
    property int elapsed: 0
    property int duration: 0
    readonly property bool connected: link.connected
    property string album: ""
    property string file: ""
    property bool repeatOn: false
    property bool singleOn: false
    // -1 from MPD when the output it is playing through has no mixer to set,
    // which is the one case the popup has nothing to offer.
    property int volume: -1

    // The queue as MPD keeps it: one entry per song, in play order, each
    // carrying the position the commands below address it by.
    property var queue: []
    // Which of those is the current song, or -1 when MPD is not playing from
    // the queue at all. It comes out of the same round trip the queue does, so
    // the two cannot be a song out of step with each other.
    property int songPos: -1

    // Raised just before `queue` is replaced, because it is replaced whole:
    // anything reading it has this one moment to note where it was.
    signal queueChanging

    // mpd's music_directory, so a song's relative path can be turned into the
    // album's directory. Album art over the protocol means readpicture/albumart
    // binary chunks; the file sitting next to the music is the same picture.
    readonly property string musicDir: Settings.musicDir
    readonly property string albumDir: file ? musicDir + file.slice(0, file.lastIndexOf("/") + 1) : ""

    // Found by listing the directory rather than by trying each candidate name
    // as an image source: a miss there is a failed file open per name, logged.
    readonly property string cover: covers.count > 0 ? covers.get(0, "fileUrl") : ""

    FolderListModel {
        id: covers
        folder: root.albumDir ? "file://" + root.albumDir : ""
        showDirs: false
        sortField: FolderListModel.Name
        nameFilters: ["cover.*", "folder.*", "front.*", "album.*"]
        caseSensitive: false
    }

    // Whether there is anything to press play on, which is not the same as
    // something playing: a stopped queue is still a queue, and the pill that
    // would start it should not be the thing that disappears when it stops.
    readonly property bool loaded: connected && (title !== "" || queue.length > 0)
    readonly property string stateIcon: state === "play" ? Theme.glyph.playing : Theme.glyph.paused
    readonly property string label: title || "Unknown"

    // off → all → one. MPD has no repeat-one of its own: it is repeat and
    // single together, single being "stop after this song" and repeat being
    // what sends it back round to the same one.
    readonly property string repeatMode: !repeatOn ? "off" : (singleOn ? "one" : "all")
    readonly property string repeatIcon: repeatMode === "one" ? Theme.glyph.repeatOne : repeatMode === "all" ? Theme.glyph.repeatAll : Theme.glyph.repeatOff

    function clock(seconds) {
        const m = Math.floor(seconds / 60);
        const s = Math.floor(seconds % 60);
        return `${m}:${s < 10 ? "0" : ""}${s}`;
    }

    // mpc's words, spoken over the command socket. The buttons and the bar's
    // scroll were written in mpc's vocabulary and there is no reason to
    // rewrite them; a process per press was what those words cost when they
    // were handed to mpc itself. Anything not translated here still goes to
    // mpc, so a new caller is never silently dropped.
    function send(args): void {
        const verb = args[0];
        const arg = args[1];
        switch (verb) {
        case "toggle":
            // `mpc toggle` starts a stopped queue; MPD's bare `pause` would
            // not, and the pill's play button is pressed on a stopped queue
            // more often than on a paused one.
            root.run([root.state === "play" ? "pause 1" : root.state === "pause" ? "pause 0" : "play"]);
            return;
        case "pause":
            root.run(["pause 1"]);
            return;
        case "prev":
            root.run(["previous"]);
            return;
        case "next":
            root.run(["next"]);
            return;
        case "seek":
            // "+10" and "-10" as they are; anything else is seconds.
            root.run(["seekcur " + arg]);
            return;
        case "volume":
            root.run([/^[+-]/.test(arg) ? "volume " + arg : "setvol " + arg]);
            return;
        case "repeat":
        case "single":
            root.run([verb + " " + (arg === "on" ? "1" : "0")]);
            return;
        default:
            Quickshell.execDetached(["mpc"].concat(args));
        }
    }

    // Nothing left to hear it through — the headphones came out and there is
    // no speaker behind them, or the output went away altogether — and the
    // record pauses rather than playing on to nobody, the way a phone does
    // when the headphones are pulled. Audio.connected is the same jack
    // detection the bar's audio icon goes by.
    //
    // Only on the way out, never back in: plugging in again is not a request
    // to start playing. And after a moment rather than at once, because a
    // switch between two outputs passes through "neither" for as long as the
    // port probe takes to answer, and that is not a disconnection.
    Connections {
        target: Audio

        function onConnectedChanged() {
            if (Audio.connected)
                unplugged.stop();
            else
                unplugged.restart();
        }
    }

    Timer {
        id: unplugged
        interval: 500
        onTriggered: if (!Audio.connected && root.state === "play")
            root.send(["pause"])
    }

    // Putting the daemon down, which `mpc stop` does not: that ends playback
    // and leaves mpd up, still holding the output. Through systemd because
    // that is what brought it up — and mpd.socket is disabled on this machine,
    // so nothing activates it straight back when the links below retry.
    function stopServer() {
        Quickshell.execDetached(["systemctl", "--user", "stop", "mpd.service"]);
    }

    // And back up, from the launcher's & mode. A process rather than a detached
    // call, because the moment it exits is the moment to dial: mpd.service is
    // Type=notify, so systemctl returns once mpd says it is ready — and the
    // links may by then have backed off to a retry most of a minute away.
    //
    // And then play, because the row says "start music", not "start mpd".
    // mpd comes back in whatever state it was put down in, which is paused
    // more often than not: a pause is how the evening usually ends, and
    // pulling the headphones out makes one (see `unplugged` above). `play`
    // resumes a paused song where it was and starts a stopped one, and
    // run() holds it for the command link if that is not up yet.
    function startServer() {
        starter.running = true;
    }

    readonly property bool starting: starter.running

    Process {
        id: starter
        command: ["systemctl", "--user", "start", "mpd.service"]
        onExited: function (exitCode) {
            link.dialNow();
            cmdLink.dialNow();
            if (exitCode === 0)
                root.run(["play"]);
        }
    }

    // The same steps the bar's own volume icon takes, so the player's level
    // and the system's are read off the same shapes.
    readonly property string volumeIcon: Audio.level(volume, false)

    // A drag hands over a new value every pixel it crosses. Only the latest
    // is worth sending; the ones behind it are already out of date.
    property int volumeTarget: -1

    // mpd has no mute, so it is a volume of nothing and the level to come back
    // to. Kept on the service rather than in the popup, which is built and
    // thrown away with every hover — a mute that forgets what it muted is
    // worse than no mute at all.
    property int premute: -1

    function toggleMute() {
        if (volume > 0) {
            premute = volume;
            setVolume(0);
        } else {
            setVolume((premute > 0 ? premute : 100) / 100);
        }
    }

    function setVolume(fraction) {
        volumeTarget = Math.round(Math.max(0, Math.min(1, fraction)) * 100);
        // The level moves now, not when mpd gets round to mentioning it. The
        // popup's bar and its readout are drawn off this property, and a drag
        // that has to wait for the write, the round trip and the idle report
        // before the fill catches up is a drag the bar does not follow.
        if (volume >= 0)
            volume = volumeTarget;
        volumeWrite.pending = true;
        if (!volumeWrite.running)
            volumeWrite.start();
    }

    // When the last volume and seek were written, so commit() knows which of
    // mpd's answers are older than the hand on the slider. Every write makes
    // mpd report a change, and the status that answers it can still carry the
    // level from before the write it is answering; letting that through is
    // the slider jumping back mid-drag.
    property real volumeSentAt: 0
    property real seekSentAt: 0
    readonly property int holdMs: 200

    // Throttled rather than held to the end of the drag: volume is a thing you
    // set by ear, and a slider that stays silent until you stop moving is one
    // you have to aim at instead of listen to. Repeating, and stopping itself
    // on the first tick with nothing new to say, so the last value of a burst
    // is always the one that lands.
    Timer {
        id: volumeWrite
        interval: 60
        repeat: true
        // Whether there is anything left to say. A flag rather than the last
        // value written: mpd has other clients, and a level this one happens
        // to have sent before is still worth sending if one of them has moved
        // it since.
        property bool pending: false
        onTriggered: {
            if (!pending || root.volumeTarget < 0) {
                stop();
                return;
            }
            pending = false;
            root.volumeSentAt = Date.now();
            root.run(["setvol " + root.volumeTarget]);
        }
    }

    // The same burst, and the same answer — except that seeking is not
    // something you do by ear. Mid-drag seeks would have mpd restarting
    // playback a dozen times on the way to the place you meant, so only the
    // last one is sent. The position the popup draws comes from `elapsed`,
    // which moves with the finger in the meantime.
    property int seekTarget: -1

    function seekTo(fraction) {
        if (duration <= 0)
            return;
        seekTarget = Math.round(Math.max(0, Math.min(1, fraction)) * duration);
        elapsed = seekTarget;
        seekWrite.restart();
    }

    Timer {
        id: seekWrite
        interval: 60
        onTriggered: {
            if (root.seekTarget < 0)
                return;
            root.seekSentAt = Date.now();
            root.run(["seekcur " + root.seekTarget]);
        }
    }

    function cycleRepeat() {
        if (repeatMode === "off") {
            run(["repeat 1"]);
        } else if (repeatMode === "all") {
            run(["single 1"]);
        } else {
            // Single has to come off with it. Left on by itself it is still
            // "stop after this song", and playback would come to a halt at the
            // end of every track rather than going back to a plain queue.
            run(["repeat 0", "single 0"]);
        }
    }

    // --- the queue ---------------------------------------------------------
    // Positions are MPD's own Pos, counted from zero, which is what the rows
    // carry.
    function playAt(pos) {
        run(["play " + pos]);
    }

    function removeAt(pos) {
        run(["delete " + pos]);
    }

    function moveTo(from, to) {
        if (to < 0 || to >= root.queue.length)
            return;
        run(["move " + from + " " + to]);
    }

    // --- playlists ---------------------------------------------------------

    // The stored playlists, by name. Asked for with the status on connect and
    // again whenever `idle` says they changed.
    property var playlists: []

    // Whether the popup's playlist section is folded open. Here rather than in
    // the popup for the same reason `premute` is: the popup is built and
    // thrown away with every hover, and a section that forgot it was open
    // would be one that never stayed open.
    property bool playlistsOpen: false

    // The database was rescanned, so every file path and tag the launcher's
    // library is holding is now a guess. Raised rather than acted on: nothing
    // here owns that copy. See services/Library.qml.
    signal databaseChanged

    // --- commands ----------------------------------------------------------

    // The connection everything is sent over. It buys three things mpc
    // cannot:
    //
    // Exact adds. The launcher hands over the files it is already holding
    // rather than a `findadd albumartist "..." album "..."`, which would miss
    // the two hundred files here carrying no albumartist and the rips whose
    // album tag is not the album's name.
    //
    // One round trip. Queueing an artist is a couple of hundred adds, and
    // replacing the queue is a clear, those adds and a play. That is one write
    // and one OK, where `mpc && mpc && mpc` is three processes and three
    // connections of their own — and three separate execDetached calls are not
    // ordered against each other at all.
    //
    // Positions. MPD takes one on `add` and on `load`, so "play next" is an
    // insert rather than an append followed by a move. mpc exposes neither.
    MpdLink {
        id: cmdLink
        path: Settings.mpdSocket

        // Nothing here asks a question, so every reply is an OK to be dropped
        // — except the greeting, which is the moment to send what was typed
        // while the link was down, and the ACK that says a command was
        // refused, which is worth a line in the log rather than a queue that
        // quietly did not change.
        onLine: line => {
            if (line.startsWith("OK MPD"))
                root.flush();
            else if (line.startsWith("ACK"))
                console.warn("mpd refused:", line);
        }
    }

    // Whatever could not be sent while the link was down, once it is up.
    function flush(): void {
        if (!root.outbox)
            return;
        cmdLink.write(root.outbox);
        root.outbox = "";
    }

    Timer {
        // mpd hangs up on a client that has said nothing for
        // connection_timeout, which is sixty seconds and is not set in
        // mpd.conf here. This socket is silent by design between keypresses,
        // so without a word from it now and then it spends the session being
        // dropped and redialled — measured at one round of that a minute — and
        // a command typed in the gap would go to the outbox rather than to
        // mpd. A ping is two bytes and an OK.
        //
        // Half the timeout rather than just inside it: the point is to be
        // nowhere near the edge, not to win a race with it.
        interval: 30000
        repeat: true
        running: cmdLink.connected
        onTriggered: cmdLink.write("ping\n")
    }

    // What could not be sent because the connection was down, so that pressing
    // Enter during a reconnect is not silently nothing. One slot: these arrive
    // on a keypress, and a second one queued behind a dead socket is a command
    // whose moment has passed.
    property string outbox: ""

    // MPD's quoting. A backslash and a double quote are the two characters
    // that mean something inside one, and an album called 12" is not rare
    // enough to leave to chance.
    function quote(s) {
        return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
    }

    function run(commands): void {
        if (!commands.length)
            return;
        // A list even for the single commands, so there is one shape to read
        // and one reply to expect.
        const text = "command_list_begin\n" + commands.join("\n") + "\ncommand_list_end\n";
        if (cmdLink.connected) {
            cmdLink.write(text);
        } else {
            // A command is the one thing worth dialling early for: the link's
            // slow retry is tuned for an mpd that is off for the evening, not
            // for one that was just started and asked to play.
            root.outbox = text;
            cmdLink.wake();
        }
    }

    // Where a batch of files goes. "queue" is the end of it, "play" is instead
    // of everything already there, "next" is straight after whatever is
    // playing — which is the one of the three that has to count.
    function enqueue(files, mode): void {
        if (!files || !files.length)
            return;
        const commands = [];
        if (mode === "play")
            commands.push("clear");
        // Absolute positions rather than MPD's relative +0. Sending a hundred
        // of those would put every file directly after the current song, so
        // the album would arrive backwards.
        const at = root.songPos + 1;
        for (let i = 0; i < files.length; i++)
            commands.push("add " + root.quote(files[i]) + (mode === "next" ? " " + (at + i) : ""));
        if (mode === "play")
            commands.push("play");
        root.run(commands);
    }

    function loadPlaylist(name, mode): void {
        if (!name)
            return;
        const commands = [];
        if (mode === "play")
            commands.push("clear");
        // The whole of it, written as the range 0:, because a position is only
        // accepted after one.
        commands.push("load " + root.quote(name) + (mode === "next" ? " 0: " + (root.songPos + 1) : ""));
        if (mode === "play")
            commands.push("play");
        root.run(commands);
    }

    // The playlist whose delete button has been pressed once, waiting to be
    // pressed again. Here rather than in the popup for the reason the rest of
    // this section is, and cleared when the pointer leaves the row — an armed
    // delete that outlives the pointer is a landmine, and the whole point of
    // the second press is that the first one was not a decision yet.
    //
    // The same second look Power.arm gives shutting the machine down, which is
    // the other thing this shell can do that cannot be undone. A song dropped
    // from the queue is a song still on the disk; a playlist is only ever this
    // file, and nothing here would be able to put it back.
    property string armedPlaylist: ""

    function removePlaylist(name): void {
        if (!name)
            return;
        root.armedPlaylist = "";
        root.run(["rm " + root.quote(name)]);
    }

    // --- protocol ----------------------------------------------------------
    property bool idling: false
    property var pending: ({})
    property var changes: []
    property var names: []

    // What the command list in flight asked, in order, and which of those
    // the lines coming in belong to. The replies arrive back to back in the
    // order they were asked for, separated by list_OK, so this is what tells
    // a queued song's Title from the current one's rather than the keys
    // having to be unique across the lot.
    property var asked: []
    property int section: 0

    // The queue is the expensive part of a refresh — a few hundred lines for
    // a long one — and it only moves when it is edited. So it is fetched by
    // difference: status carries the queue's version, `plchanges` answers
    // with only the songs touched since the version given, and the array is
    // patched rather than replaced from scratch. Zero is "everything", which
    // is what a fresh connection asks for.
    property bool queueStale: true
    property int queueVersion: 0
    property bool playlistsStale: true

    // Onto the status socket, which only exists while the connection does.
    // Nothing is queued for one that is missing: everything this file sends
    // over it is asked for again by the greeting on the way back up.
    function say(text): void {
        link.write(text);
    }

    function query() {
        idling = false;
        section = 0;
        pending = {};
        changes = [];
        names = [];
        // One round trip for all of it, rather than a request/response pair
        // each. The _ok_ form is what puts the list_OK between the replies.
        const commands = ["status", "currentsong"];
        if (queueStale)
            commands.push("plchanges " + queueVersion);
        if (playlistsStale)
            commands.push("listplaylists");
        queueStale = false;
        playlistsStale = false;
        asked = commands.map(c => c.split(" ")[0]);
        root.say("command_list_ok_begin\n" + commands.join("\n") + "\ncommand_list_end\n");
    }

    function idle() {
        idling = true;
        // Only the subsystems the bar renders; anything else stays silent.
        // The last two are not the bar's: they are the launcher's & mode,
        // whose library is a copy of the database and whose first screen is
        // the stored playlists. Both move rarely enough to cost nothing —
        // `database` only when mpd rescans the disk.
        root.say("idle player mixer options playlist database stored_playlist\n");
    }

    function commit() {
        const now = Date.now();
        root.state = pending["state"] ?? "stop";
        root.title = pending["Title"] ?? pending["Name"] ?? (pending["file"] ? pending["file"].split("/").pop() : "");
        root.artist = pending["Artist"] ?? "";
        root.album = pending["Album"] ?? "";
        root.file = pending["file"] ?? "";
        root.duration = Math.round(parseFloat(pending["duration"] ?? pending["Time"] ?? "0"));
        root.songPos = pending["song"] === undefined ? -1 : parseInt(pending["song"]);
        root.repeatOn = pending["repeat"] === "1";
        // MPD reports single as 0/1/oneshot.
        root.singleOn = (pending["single"] ?? "0") !== "0";
        // Not while the hand is still on the slider, or just off it: see
        // volumeSentAt.
        if (!seekWrite.running && now - root.seekSentAt > root.holdMs)
            root.elapsed = Math.round(parseFloat(pending["elapsed"] ?? "0"));
        if (!volumeWrite.running && now - root.volumeSentAt > root.holdMs)
            root.volume = parseInt(pending["volume"] ?? "-1");

        if (root.asked.includes("listplaylists"))
            root.playlists = root.names;

        const version = parseInt(pending["playlist"] ?? "0");
        if (!root.asked.includes("plchanges")) {
            // A version that moved without `idle` saying so — a change that
            // landed between the query and the idle — is fetched on the next
            // pass rather than waited out.
            if (version !== root.queueVersion)
                root.queueStale = true;
            return;
        }

        const length = parseInt(pending["playlistlength"] ?? "0");
        const next = root.queue.slice(0, length);
        for (const song of root.changes) {
            const pos = parseInt(song["Pos"]);
            if (isNaN(pos) || pos >= length)
                continue;
            next[pos] = {
                pos: pos,
                title: song["Title"] ?? song["Name"] ?? (song["file"] ? song["file"].split("/").pop() : ""),
                artist: song["Artist"] ?? "",
                duration: Math.round(parseFloat(song["Time"] ?? "0"))
            };
        }
        // A gap means the difference did not cover the queue — which should
        // not happen, and is answered with the whole thing rather than a
        // queue with a hole in it.
        if (next.length < length || next.some(s => s === undefined)) {
            root.queueVersion = 0;
            root.queueStale = true;
            return;
        }
        root.queueVersion = version;
        root.queueChanging();
        root.queue = next;
    }

    // The status connection, parked in `idle` between refreshes.
    MpdLink {
        id: link
        path: Settings.mpdSocket
        onLine: line => root.receive(line)
    }

    function receive(line): void {
        if (line.startsWith("OK MPD")) {
            root.queueVersion = 0;
            root.queueStale = true;
            root.playlistsStale = true;
            root.query();
            return;
        }
        if (line === "list_OK") {
            root.section++;
            return;
        }
        if (line === "OK") {
            if (root.idling) {
                root.query();
                return;
            }
            root.commit();
            // Straight back round when the commit found something it still
            // needs, rather than idling on a queue known to be wrong.
            if (root.queueStale)
                root.query();
            else
                root.idle();
            return;
        }
        if (line.startsWith("ACK")) {
            // Whatever was being asked for is lost with the rest of the
            // command list, the queue included.
            root.queueVersion = 0;
            root.queueStale = true;
            root.query();
            return;
        }
        const split = line.indexOf(": ");
        if (split < 0)
            return;
        const key = line.slice(0, split);
        const value = line.slice(split + 2);

        if (root.idling) {
            // `idle` answers with the subsystems that moved. Two are worth
            // remembering — everything else is in the status the next query
            // asks for regardless, or is somebody else's to go and fetch.
            if (key === "changed") {
                if (value === "playlist")
                    root.queueStale = true;
                else if (value === "stored_playlist")
                    root.playlistsStale = true;
                else if (value === "database")
                    root.databaseChanged();
            }
            return;
        }

        const reply = root.asked[root.section];
        if (reply === "plchanges") {
            // Songs run together with nothing between them; `file` is the
            // first line of each.
            if (key === "file")
                root.changes.push({
                    file: value
                });
            else if (root.changes.length > 0)
                root.changes[root.changes.length - 1][key] = value;
        } else if (reply === "listplaylists") {
            if (key === "playlist")
                root.names.push(value);
        } else {
            // status and currentsong, merged: they share no key that means
            // two different things.
            root.pending[key] = value;
        }
    }

    // Losing the connection is losing everything that was read over it.
    onConnectedChanged: {
        if (root.connected)
            return;
        root.state = "stop";
        root.queueChanging();
        root.queue = [];
        root.songPos = -1;
        root.queueVersion = 0;
        root.queueStale = true;
    }

    // `idle` reports that the song changed, not that a second passed, so the
    // elapsed time in the popup needs its own tick while something is playing.
    Timer {
        interval: 1000
        repeat: true
        running: root.state === "play"
        onTriggered: root.elapsed++
    }
}

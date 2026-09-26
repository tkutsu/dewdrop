pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import qs

// MPD state, straight off the MPD protocol.
//
// mpd publishes no MPRIS, so Services.Mpris cannot see it and the waybar module
// polled every 5 seconds instead. MPD's own `idle` command pushes changes as
// they happen, so this sits silent until something actually moves.
//
// Playback commands go through mpc: sending on an idling connection means a
// noidle handshake that has to be unwound around every response, and mpc is
// already the vocabulary these buttons were written in.
Singleton {
    id: root

    property string state: "stop"
    property string title: ""
    property string artist: ""
    property int elapsed: 0
    property int duration: 0
    // Read off the live socket rather than set by its signal: a socket is
    // already open by the time a handler on it would be attached, so the first
    // change never arrives. Null while the connection is being rebuilt — see
    // the note above the Loader that holds it.
    readonly property bool connected: link.item ? link.item.connected : false
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
    readonly property string musicDir: "/files/_media/_music/"
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

    function send(args) {
        Quickshell.execDetached(["mpc"].concat(args));
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
    // so nothing activates it straight back when the socket below retries.
    function stopServer() {
        Quickshell.execDetached(["systemctl", "--user", "stop", "mpd.service"]);
    }

    // The same four steps the bar's own volume icon takes, so the player's
    // level and the system's are read off the same shapes.
    readonly property string volumeIcon: volume <= 0 ? Theme.glyph.muted : volume < 34 ? Theme.glyph.volLow : volume < 67 ? Theme.glyph.volMed : Theme.glyph.volHigh

    // A drag hands over a new value every pixel it crosses, and every one of
    // them would be an mpc process of its own. Only the latest is worth
    // spawning; the ones behind it are already out of date.
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
            root.send(["volume", String(root.volumeTarget)]);
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
        // Seconds, where this used to send a percentage. Two significant
        // figures over a four-minute track is a landing point two seconds
        // from the one the bar was dropped on, and now that the bar stays
        // where it was dropped, that gap is something you can see.
        seekTarget = Math.round(Math.max(0, Math.min(1, fraction)) * duration);
        elapsed = seekTarget;
        seekWrite.restart();
    }

    Timer {
        id: seekWrite
        interval: 60
        onTriggered: if (root.seekTarget >= 0)
            root.send(["seek", root.clock(root.seekTarget)])
    }

    function cycleRepeat() {
        if (repeatMode === "off") {
            send(["repeat", "on"]);
        } else if (repeatMode === "all") {
            send(["single", "on"]);
        } else {
            send(["repeat", "off"]);
            // Single has to come off with it. Left on by itself it is still
            // "stop after this song", and playback would come to a halt at the
            // end of every track rather than going back to a plain queue.
            send(["single", "off"]);
        }
    }

    // --- the queue ---------------------------------------------------------
    // mpc counts the queue from one; MPD's own Pos, which is what the rows
    // carry, counts from zero.
    function playAt(pos) {
        send(["play", String(pos + 1)]);
    }

    function removeAt(pos) {
        send(["del", String(pos + 1)]);
    }

    function moveTo(from, to) {
        if (to < 0 || to >= root.queue.length)
            return;
        send(["move", String(from + 1), String(to + 1)]);
    }

    // --- playlists ---------------------------------------------------------

    // The stored playlists, by name. Read once at startup and then only when
    // MPD says they changed — see the idle subsystems below.
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

    Process {
        id: playlistList

        command: ["mpc", "lsplaylists"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.playlists = text.split("\n").filter(l => l.length)
        }
    }

    // --- commands ----------------------------------------------------------

    // A second connection, which never idles.
    //
    // The socket below is parked in `idle`, and sending on it means a noidle
    // handshake to unwind around every reply — which is why the transport
    // buttons shell out to mpc. A connection of its own has none of that
    // problem, and buys three things mpc cannot:
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
    //
    // Rebuilt rather than re-dialled, the same way and for the same reason as
    // the status socket further down.
    Loader {
        id: cmdLink

        sourceComponent: Component {
            Socket {
                id: sock

                path: Quickshell.env("XDG_RUNTIME_DIR") + "/mpd.sock"
                connected: true

                // A fresh socket is already open by the time this runs and so
                // has no change to report; a re-dialled one reports the change
                // and never runs this. Between the two, every way the link can
                // come up ends in a flush.
                //
                // Handed to the flush rather than looked up there: a Loader
                // sets its `item` only once the object inside it is finished,
                // which is after this runs (checked against this build). Read
                // through `cmdLink.item`, the flush on a freshly built socket
                // would find null, decide it was not connected, and leave the
                // one command the outbox exists for sitting in it.
                Component.onCompleted: root.flush(sock)
                onConnectedChanged: if (sock.connected)
                    root.flush(sock)

                parser: SplitParser {
                    // Nothing here asks a question, so every reply is an OK to be
                    // dropped — except the ACK that says a command was refused, which
                    // is worth a line in the log rather than a queue that quietly did
                    // not change.
                    onRead: function (line) {
                        if (line.startsWith("ACK"))
                            console.warn("mpd refused:", line);
                    }
                }
            }
        }
    }

    readonly property bool cmdConnected: cmdLink.item ? cmdLink.item.connected : false

    // Whatever could not be sent while the link was down, once it is up.
    function flush(sock): void {
        if (!root.outbox || !sock || !sock.connected)
            return;
        sock.write(root.outbox);
        root.outbox = "";
    }

    Timer {
        id: cmdReconnect
        interval: 5000
        repeat: true
        running: !root.cmdConnected
        onTriggered: {
            cmdLink.active = false;
            cmdLink.active = true;
        }
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
        running: root.cmdConnected
        onTriggered: cmdLink.item.write("ping\n")
    }

    // What could not be sent because the connection was down, so that pressing
    // Enter during the five seconds of a reconnect is not silently nothing.
    // One slot: these arrive on a keypress, and a second one queued behind a
    // dead socket is a command whose moment has passed.
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
        if (root.cmdConnected)
            cmdLink.item.write(text);
        else
            root.outbox = text;
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
    property var songs: []

    // Which reply of the command list the lines coming in belong to. The
    // replies arrive back to back in the order they were asked for, separated
    // by list_OK, so this is what tells a song's Title from the current one's
    // rather than the keys having to be unique across all three.
    property int section: 0

    // The queue is the expensive part of a refresh — a few hundred lines for a
    // long one — and it only moves when it is edited. So it is asked for on
    // connect and then only when `idle` says the playlist changed, rather than
    // on every song boundary and every seek.
    property bool queueStale: true
    property bool queueAsked: false

    // Onto the status socket, which only exists while the connection does.
    // Nothing is queued for one that is missing: everything this file sends
    // over it is asked for again by the greeting on the way back up.
    function say(text): void {
        if (link.item)
            link.item.write(text);
    }

    function query() {
        idling = false;
        section = 0;
        pending = {};
        songs = [];
        queueAsked = queueStale;
        queueStale = false;
        // One round trip for all of it, rather than a request/response pair
        // each. The _ok_ form is what puts the list_OK between the replies.
        const commands = queueAsked ? ["status", "currentsong", "playlistinfo"] : ["status", "currentsong"];
        root.say("command_list_ok_begin\n" + commands.join("\n") + "\ncommand_list_end\n");
    }

    function idle() {
        idling = true;
        // Only the subsystems the bar renders; anything else stays silent.
        // The last two are not the bar's: they are the launcher's # mode,
        // whose library is a copy of the database and whose first screen is
        // the stored playlists. Both move rarely enough to cost nothing —
        // `database` only when mpd rescans the disk.
        root.say("idle player mixer options playlist database stored_playlist\n");
    }

    function commit() {
        root.state = pending["state"] ?? "stop";
        root.title = pending["Title"] ?? pending["Name"] ?? (pending["file"] ? pending["file"].split("/").pop() : "");
        root.artist = pending["Artist"] ?? "";
        root.album = pending["Album"] ?? "";
        root.file = pending["file"] ?? "";
        root.elapsed = Math.round(parseFloat(pending["elapsed"] ?? "0"));
        root.duration = Math.round(parseFloat(pending["duration"] ?? pending["Time"] ?? "0"));
        root.songPos = pending["song"] === undefined ? -1 : parseInt(pending["song"]);
        root.repeatOn = pending["repeat"] === "1";
        // MPD reports single as 0/1/oneshot.
        root.singleOn = (pending["single"] ?? "0") !== "0";
        root.volume = parseInt(pending["volume"] ?? "-1");

        if (!root.queueAsked)
            return;

        const next = [];
        for (const song of root.songs)
            next.push({
                pos: parseInt(song["Pos"] ?? String(next.length)),
                title: song["Title"] ?? song["Name"] ?? (song["file"] ? song["file"].split("/").pop() : ""),
                artist: song["Artist"] ?? "",
                duration: Math.round(parseFloat(song["Time"] ?? "0"))
            });
        root.queueChanging();
        root.queue = next;
    }

    // The connection is rebuilt rather than re-dialled.
    //
    // A Socket whose *first* connect fails is dead for good in Quickshell
    // 0.3.1: `connected` never changes, so nothing hears about the failure,
    // and neither assigning `connected = true` again nor reassigning `path`
    // makes it try a second time — measured against this build, not assumed.
    // A drop from a connection that did come up does re-dial, but the two
    // arrive together whenever mpd is stopped rather than merely absent, so
    // both go the same way: throw the object away and build another.
    Loader {
        id: link

        sourceComponent: Component {
            Socket {
                path: Quickshell.env("XDG_RUNTIME_DIR") + "/mpd.sock"
                connected: true

                parser: SplitParser {
                    onRead: function (line) {
                        if (line.startsWith("OK MPD")) {
                            root.queueStale = true;
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
                            } else {
                                root.commit();
                                root.idle();
                            }
                            return;
                        }
                        if (line.startsWith("ACK")) {
                            // Whatever was being asked for is lost with the rest of the
                            // command list, the queue included.
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
                            // `idle` answers with the subsystems that moved. The queue
                            // is the only one worth remembering — everything else is
                            // in the status the next query asks for regardless, or is
                            // somebody else's to go and fetch.
                            if (key === "changed") {
                                if (value === "playlist")
                                    root.queueStale = true;
                                else if (value === "stored_playlist")
                                    playlistList.running = true;
                                else if (value === "database")
                                    root.databaseChanged();
                            }
                        } else if (root.section < 2) {
                            // status and currentsong, merged: they share no key that
                            // means two different things.
                            root.pending[key] = value;
                        } else if (key === "file") {
                            // playlistinfo runs the songs together with nothing between
                            // them; `file` is the first line of each.
                            root.songs.push({
                                file: value
                            });
                        } else if (root.songs.length > 0) {
                            root.songs[root.songs.length - 1][key] = value;
                        }
                    }
                }
            }
        }
    }

    // Losing the connection is losing everything that was read over it. Here
    // rather than on the socket: the object that would have reported it is
    // the one being thrown away.
    onConnectedChanged: {
        if (root.connected)
            return;
        root.state = "stop";
        root.queueChanging();
        root.queue = [];
        root.songPos = -1;
        root.queueStale = true;
    }

    // Runs only while there is nothing on the other end, which is all three
    // ways of getting there at once: mpd down at login, mpd stopped from the
    // popup, and a rebuild that found it still gone.
    Timer {
        id: reconnect
        interval: 5000
        repeat: true
        running: !root.connected
        onTriggered: {
            link.active = false;
            link.active = true;
        }
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

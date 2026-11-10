pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Who is listening and who is watching: the apps taking sound from a
// microphone right now, and the ones taking a picture of the screen. The
// bar's answer to the Mac's recording indicator (modules/Recording.qml).
//
// Read off PipeWire's links rather than its nodes. An app can hold a capture
// stream open long after it stopped listening (a call on hold, a tab that
// once asked), and the Bluetooth stack keeps one of its own; what counts is a
// link running from a real source into an app, and only while it is Active.
// A paused one, a corked stream, is an app that could listen and is not.
//
// A screen share is a video source that is not a camera: the portal's stream
// (xdg-desktop-portal-hyprland makes one node per share) linked into the app
// that asked for it.
Singleton {
    id: root

    readonly property var groups: Pipewire.linkGroups.values.filter(g => g.state === PwLinkState.Active && g.source && g.target)

    // Mic: a source (not a sink's monitor, which is the sound going out, not
    // in) into an app's capture stream. Not the Bluetooth stack's own
    // ("Internal"), and not a level meter (stream.monitor, pavucontrol's).
    readonly property var micLinks: root.groups.filter(g => g.source?.type === PwNodeType.AudioSource && g.target?.type === PwNodeType.AudioInStream && !String(g.target.properties?.["media.class"] ?? "").includes("Internal") && String(g.target.properties?.["stream.monitor"]) !== "true")

    // Video input streams can be Untracked in Quickshell's node type flags.
    readonly property var shareLinks: root.groups.filter(g => g.source?.type === PwNodeType.VideoSource && !root.camera(g.source) && ((g.target?.type & PwNodeType.Stream) || g.target?.properties?.["media.class"] === "Stream/Input/Video"))

    // One entry per app stream, with the source it is listening to.
    readonly property var mics: {
        const seen = new Map();
        for (const g of root.micLinks)
            if (!seen.has(g.target.id))
                seen.set(g.target.id, { node: g.target, source: g.source, app: root.appName(g.target) });
        return [...seen.values()];
    }

    // One entry per share, with every app it goes to.
    readonly property var shares: {
        const seen = new Map();
        for (const g of root.shareLinks) {
            const entry = seen.get(g.source.id) ?? { source: g.source, apps: [] };
            const app = root.appName(g.target);
            if (!entry.apps.includes(app))
                entry.apps.push(app);
            seen.set(g.source.id, entry);
        }
        return [...seen.values()];
    }

    readonly property bool listening: root.mics.length > 0
    readonly property bool sharing: root.shares.length > 0
    readonly property bool active: root.listening || root.sharing
    readonly property bool microphonesMuted: root.listening && root.mics.every(m => root.muted(m))
    readonly property bool recording: root.sharing || root.mics.some(m => !root.muted(m) && (m.node?.audio?.volume ?? 1) > 0 && (m.source?.audio?.volume ?? 1) > 0)

    // One input control per device, even when several apps capture from it.
    readonly property var inputs: {
        const seen = new Map();
        for (const mic of root.mics)
            seen.set(mic.source.id, mic.source);
        return [...seen.values()];
    }

    // "Firefox is using the microphone", for the tooltip and the popup's title.
    readonly property string summary: {
        const parts = [];
        if (root.listening)
            parts.push(root.names(root.mics.map(m => m.app)) + " using the microphone" + (root.microphonesMuted ? " (muted)" : root.mics.some(m => root.muted(m)) ? " (some muted)" : ""));
        if (root.sharing)
            parts.push(root.names([].concat(...root.shares.map(s => s.apps))) + " sharing the screen");
        return parts.join(" · ");
    }

    function names(list: var): string {
        const unique = [...new Set(list)];
        return unique.length > 2 ? unique.slice(0, 2).join(", ") + " and " + (unique.length - 2) + " more" : unique.join(" and ");
    }

    function camera(node): bool {
        const api = node.properties?.["device.api"] ?? "";
        return api === "v4l2" || api === "libcamera";
    }

    function appName(node): string {
        const props = node.properties ?? {};
        if (props["application.name"])
            return props["application.name"];
        DesktopEntries.applications.values.length;
        return DesktopEntries.heuristicLookup(props["application.id"] || props["application.process.binary"] || node.name)?.name || props["node.description"] || node.description || node.name || "An app";
    }

    // Either the app or its input can silence a capture; other apps stay live.
    function muted(mic): bool {
        return !!(mic.node?.audio?.muted || mic.source?.audio?.muted);
    }

    // Portal IDs identify sessions rather than the screen the user chose.
    function shareName(source): string {
        const label = source.properties?.["node.description"] || source.description || source.properties?.["media.name"] || source.name;
        return !label || /^(xdph-streaming|xdg-desktop-portal)/.test(label) ? "Screen capture" : label;
    }

    // One app's capture, muted at its own stream: that app hears silence and
    // nothing else changes.
    function toggleApp(node): void {
        if (node?.audio)
            node.audio.muted = !node.audio.muted;
    }

    // Muting an input affects every app that captures from that device.
    function toggleInput(source): void {
        if (source?.audio)
            source.audio.muted = !source.audio.muted;
    }

    // The share's node destroyed, which ends it for every app it went to,
    // the way the Mac's Stop Sharing does; the app sees the stream end.
    function stopShare(source): void {
        if (source)
            Quickshell.execDetached(["pw-cli", "destroy", String(source.id)]);
    }

    // Bind links before filtering by state: untracked links report Unlinked.
    // Their nodes also need tracking for app properties and stream mute.
    // Spread rather than flatMap, which Qt's JavaScript engine lacks.
    PwObjectTracker {
        objects: [].concat(Pipewire.linkGroups.values, ...Pipewire.linkGroups.values.map(g => [g.source, g.target]))
    }
}

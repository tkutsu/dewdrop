pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.components

// Shared forecasts and saved city; requests never run once per monitor.
Singleton {
    id: root

    property var location: null
    property var days: []
    property string timezone: ""
    property string trouble: ""
    property double updatedAt: 0
    property double now: Date.now() / 1000
    property string query: ""
    property var locations: []
    property string searchTrouble: ""
    property int revision: 0
    property int searchRevision: 0
    property string forecastRequest: ""
    property double cooldownUntil: 0
    property double forecastRetryAt: 0
    readonly property bool enabled: Settings.moduleOn("weather")
    readonly property bool rateLimited: root.cooldownUntil > root.now
    readonly property double nextRetryAt: Math.max(root.cooldownUntil, root.forecastRetryAt)
    readonly property bool waitingForForecast: root.nextRetryAt > root.now
    readonly property bool loading: !!forecastJob.want && (forecastJob.running || forecastJob.arg !== forecastJob.want)
    readonly property bool searching: !!searchJob.want && (searchJob.running || searchJob.arg !== searchJob.want)
    readonly property bool stale: root.updatedAt > 0 && (root.now - root.updatedAt > 1800 || root.trouble !== "")

    readonly property var upcoming: root.days.reduce((hours, day) => hours.concat(day.hours), []).filter(hour => hour.at >= root.now && hour.at < root.now + 6 * 3600)
    readonly property var outlook: root.upcoming.reduce((worst, hour) => !worst || hour.severity > worst.severity ? hour : worst, null)
    readonly property string icon: root.outlook?.icon ?? "\u{f0590}"
    readonly property string tooltip: !root.location ? "Choose a weather location" : root.outlook ? `${root.location.name}: ${root.outlook.description} in the next 6 hours${root.stale ? " (last forecast)" : ""}` : root.trouble || "Loading weather..."

    // Selecting a new city drops the previous city's data before fetching.
    function choose(place: var): void {
        root.location = place;
        stored.location = place;
        saved.writeAdapter();
        root.query = "";
    }

    function refresh(force): void {
        root.now = Date.now() / 1000;
        if (!root.location || !root.enabled)
            return;
        if (root.waitingForForecast || (force && root.loading))
            return;
        root.forecastRequest = JSON.stringify([++root.revision, root.location.latitude, root.location.longitude, root.location.timezone || "auto", force]);
    }

    function measure(value: var, suffix: string): string {
        return value === null || value === undefined ? "-" : `${Math.round(value)}${suffix}`;
    }

    onLocationChanged: {
        root.days = [];
        root.updatedAt = 0;
        root.trouble = root.waitingForForecast ? "Weather requests are paused until the retry time." : "";
        root.forecastRequest = "";
        root.refresh();
    }
    onEnabledChanged: {
        if (root.enabled)
            root.refresh();
        else
            root.forecastRequest = "";
    }
    onQueryChanged: {
        root.searchRevision++;
        root.locations = [];
        root.searchTrouble = "";
    }

    FileView {
        id: saved
        path: Paths.state("weather.json")
        printErrors: false
        onLoaded: if (!root.location && stored.location?.name && Number.isFinite(stored.location.latitude) && Number.isFinite(stored.location.longitude))
            root.location = stored.location
        JsonAdapter {
            id: stored
            property var location: null
        }
    }

    Timer {
        interval: 60000
        running: root.enabled
        repeat: true
        onTriggered: root.now = Date.now() / 1000
    }
    Timer {
        // A reload resumes the cached forecast's remaining freshness window.
        interval: root.updatedAt > 0 ? Math.max(1000, Math.min(15 * 60000, Math.ceil((root.updatedAt + 15 * 60 - Date.now() / 1000) * 1000))) : 15 * 60000
        running: root.enabled && !!root.location && !root.loading && !root.waitingForForecast
        repeat: true
        onTriggered: root.refresh()
    }
    // Wake at the helper's persisted deadline; manual refresh and reconnect
    // use the same gate and cannot shorten a provider's cooldown.
    Timer {
        id: retryWake
        interval: Math.max(1, Math.min(2147483647, Math.ceil((root.nextRetryAt - Date.now() / 1000) * 1000)))
        running: root.enabled && root.nextRetryAt > 0
        onTriggered: {
            root.now = Date.now() / 1000;
            if (root.now < root.nextRetryAt) {
                retryWake.restart();
                return;
            }
            root.forecastRetryAt = 0;
            root.cooldownUntil = 0;
            root.searchRevision++;
            root.refresh();
        }
    }
    Connections {
        target: Network
        function onOnlineChanged(): void {
            if (Network.online && root.trouble)
                root.refresh();
        }
    }

    QueuedProcess {
        id: forecastJob
        want: root.waitingForForecast ? "" : root.forecastRequest
        command: {
            if (!arg)
                return [];
            const request = JSON.parse(arg);
            return ["python3", Quickshell.shellPath("scripts/weather-fetch.py"), "forecast", String(request[1]), String(request[2]), request[3], "--state", Paths.state("weather-requests.json"), "--cache", Paths.cache("weather-forecast.json"), ...(request[4] ? ["--force"] : [])];
        }
        onResult: (request, output) => {
            const relevant = request === root.forecastRequest;
            let result;
            try { result = JSON.parse(output); } catch (e) { result = {error: "Could not read the weather forecast."}; }
            root.now = Date.now() / 1000;
            // A rate limit also applies to a city chosen while this ran.
            if (result.cooldownUntil > root.now)
                root.cooldownUntil = Math.max(root.cooldownUntil, result.cooldownUntil);
            if (!relevant)
                return;
            if (result.days?.length) {
                root.days = result.days;
                root.timezone = result.timezone;
                root.updatedAt = result.fetchedAt ?? root.now;
            }
            if (result.error || !result.days?.length) {
                root.trouble = result.error || "The forecast is unavailable.";
                root.forecastRetryAt = result.retryAt ?? root.now + 30;
                return;
            }
            root.forecastRetryAt = 0;
            root.trouble = "";
        }
    }

    QueuedProcess {
        id: searchJob
        interval: 350
        want: !root.rateLimited && root.query.trim().length >= 2 ? JSON.stringify([root.searchRevision, root.query.trim()]) : ""
        command: ["python3", Quickshell.shellPath("scripts/weather-fetch.py"), "search", arg ? JSON.parse(arg)[1] : "", "--state", Paths.state("weather-requests.json"), "--cache", Paths.cache("weather-forecast.json")]
        onResult: (request, output) => {
            const relevant = request === want;
            let result;
            try { result = JSON.parse(output); } catch (e) { result = {error: "Could not read the location results."}; }
            root.now = Date.now() / 1000;
            if (result.cooldownUntil > root.now)
                root.cooldownUntil = Math.max(root.cooldownUntil, result.cooldownUntil);
            if (!relevant)
                return;
            root.locations = result.locations ?? [];
            root.searchTrouble = result.error ?? (root.locations.length === 0 ? "No matching locations." : "");
        }
    }
}

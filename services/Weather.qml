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
    property alias feelsLike: stored.feelsLike
    property bool restored: false
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

    // Not flatMap: Qt's JavaScript engine does not have it.
    readonly property var allHours: [].concat(...root.days.map(day => day.hours))
    readonly property var thisHour: root.allHours.find(hour => hour.at <= root.now && root.now < hour.at + 3600) ?? null
    readonly property var today: root.thisHour ? root.days.find(day => day.hours.includes(root.thisHour)) ?? null : null
    readonly property var upcoming: root.allHours.filter(hour => hour.at + 3600 > root.now && hour.at < root.now + 6 * 3600)
    readonly property string summary: root.summarize(root.upcoming)
    readonly property var outlook: root.upcoming.reduce((worst, hour) => !worst || hour.severity > worst.severity ? hour : worst, null)
    readonly property string icon: root.outlook?.icon ?? "\u{f0590}"
    // The six-hour line the bar and popup share: the summary, marked when it
    // is a cached forecast, or why there is none yet.
    readonly property string nextSixHours: root.upcoming.length ? `${root.stale ? "Last forecast: " : ""}${root.summary}` : root.trouble || "Loading weather..."
    readonly property string tooltip: root.location ? `Next 6 hours: ${root.nextSixHours}` : "Choose a weather location"

    // Merge matching hourly forecasts without bridging missing hours or DST epochs.
    function hourRanges(hours: var, key: string): var {
        const ranges = [];
        for (const hour of hours) {
            const previous = ranges[ranges.length - 1];
            if (previous && (!key || previous.hour[key] === hour[key]) && previous.end === hour.at)
                previous.end = hour.at + 3600;
            else
                ranges.push({start: hour.at, end: hour.at + 3600, hour: hour});
        }
        return ranges;
    }

    // Lead with impactful weather, folding noisy hourly changes into a short
    // outlook. Hours are classed by the helper's severity scale (condition()
    // in weather-fetch.py: 0 clear, 1 partly cloudy, 2 overcast, 3 fog,
    // 4 drizzle and up wet, 6 heavy rain and up hazardous, -1 unknown), so a
    // renamed condition changes the wording here and nothing else.
    function summarize(hours: var): string {
        if (!hours.length)
            return "Forecast unavailable.";
        const finite = value => typeof value === "number" && Number.isFinite(value);
        const complete = hours[0].at <= root.now && hours[hours.length - 1].at + 3600 >= root.now + 6 * 3600 && hours.every((hour, index) => index === 0 || hour.at - hours[index - 1].at === 3600);
        const known = hours.filter(hour => hour.severity >= 0);
        const wet = hours.filter(hour => hour.severity >= 4 || finite(hour.rain) && hour.rain >= 30);

        function timing(forecast) {
            const periods = root.hourRanges(forecast, "");
            const first = forecast[0];
            if (complete && forecast.length === hours.length)
                return "throughout";
            if (periods.length > 1)
                return first.at <= root.now ? "on and off" : `on and off from ${first.time}`;
            if (first.at <= root.now)
                return "this hour";
            return `${forecast.length === 1 ? "around" : "from"} ${first.time}`;
        }

        // What is falling or hanging about, else what the sky does.
        function conditions() {
            const worst = hours.reduce((top, hour) => hour.severity > top.severity ? hour : top);
            // Fog only leads while nothing is falling.
            const hazard = worst.severity >= 6 || worst.severity === 3 && !wet.length ? worst.description : "";
            if (hazard || wet.length) {
                const likely = wet.filter(hour => finite(hour.rain) && hour.rain >= 70);
                const focus = hazard ? hours.filter(hour => hour.description === hazard) : likely.length ? likely : wet;
                const label = hazard === "Thunderstorm" ? "Thunderstorms" : hazard === "Fog" ? "Foggy" : hazard || (likely.length ? "Rain likely" : "Rain possible");
                let text = `${label} ${timing(focus)}`;
                if (root.hourRanges(focus, "").length === 1 && focus.length < hours.length) {
                    const last = wet.length ? wet[wet.length - 1] : focus[focus.length - 1];
                    const after = hours.find(hour => hour.at === last.at + 3600);
                    if (after && known.includes(after) && !wet.includes(after))
                        text += `, ${after.severity <= 1 ? "clearing" : "easing"} around ${after.time}`;
                }
                return text;
            }
            if (!known.length)
                return "Conditions unavailable";

            const ranges = root.hourRanges(known, "description");
            const last = ranges[ranges.length - 1];
            const settles = ranges.length <= 3 && last.end - last.start >= 7200;
            if (settles && known[0].severity !== 0 && last.hour.severity === 0)
                return `Cloudy at first, clearing around ${last.hour.time}`;
            if (settles && known[0].severity === 0 && last.hour.severity === 2)
                return `Clear at first, cloudier from ${last.hour.time}`;

            const clear = known.filter(hour => hour.severity === 0).length / known.length;
            const cloudy = known.filter(hour => hour.severity === 2).length / known.length;
            const sky = clear === 1 ? "Clear" : cloudy === 1 ? "Overcast" : clear >= 0.6 ? "Mostly clear" : cloudy >= 0.6 ? "Mostly cloudy" : "Partly cloudy";
            const rain = hours.map(hour => hour.rain).filter(finite);
            if (complete && known.length === hours.length && rain.length === hours.length)
                return sky + (Math.max(...rain) <= 10 ? " and dry" : " with little chance of rain");
            return sky;
        }

        function wind() {
            const winds = hours.filter(hour => finite(hour.wind));
            const peak = winds.length ? Math.max(...winds.map(hour => hour.wind)) : 0;
            if (peak < 29)
                return "";
            const threshold = peak >= 62 ? 62 : peak >= 50 ? 50 : peak >= 39 ? 39 : 29;
            const windy = winds.filter(hour => hour.wind >= threshold);
            const label = threshold === 62 ? "Gale-force winds" : threshold === 50 ? "Very strong winds" : threshold === 39 ? "Strong winds" : "Breezy";
            return `${label}${windy.length === hours.length ? "" : ` ${timing(windy)}`}`;
        }

        function temperature() {
            const temperatures = hours.map(hour => hour.temperature).filter(finite);
            if (!temperatures.length)
                return "";
            const minimum = Math.min(...temperatures);
            const maximum = Math.max(...temperatures);
            const low = Math.round(minimum);
            const high = Math.round(maximum);
            const first = hours[0].temperature;
            const last = hours[hours.length - 1].temperature;
            if (maximum >= 35)
                return `Hot, up to ${high}°C`;
            if (minimum <= 0)
                return `Freezing, down to ${low}°C`;
            if (finite(first) && finite(last) && Math.abs(Math.round(last) - Math.round(first)) >= 3)
                return `${last > first ? "Warming" : "Cooling"} to ${Math.round(last)}°C`;
            return high - low <= 2 ? `Around ${Math.round((low + high) / 2)}°C` : `Around ${low}-${high}°C`;
        }

        const sentences = [conditions(), wind(), temperature()].filter(sentence => sentence !== "");
        if (!complete)
            sentences.push("Some hours are missing");
        else if (known.length < hours.length)
            sentences.push("Some conditions are unavailable");
        return sentences.join(". ") + ".";
    }

    // Calendar labels come from the forecast city, including cached days.
    function dayLabel(day: var): string {
        if (!root.today)
            return day.weekday;
        const offset = Math.round((Date.parse(day.date) - Date.parse(root.today.date)) / 86400000);
        return offset === 0 ? "Today" : offset === 1 ? "Tomorrow" : day.weekday;
    }

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

    // Short Beaufort strength labels for the hourly wind speed in km/h.
    function windLabel(speed: var): string {
        if (typeof speed !== "number" || !Number.isFinite(speed) || speed < 0)
            return "Wind";
        const limits = [1, 12, 20, 29, 39, 50, 62, 75, 89, 103, 118];
        const labels = ["Calm", "Light", "Gentle", "Moderate", "Fresh", "Strong", "Near gale", "Gale", "Strong gale", "Storm", "Violent storm", "Hurricane"];
        const band = limits.findIndex(limit => speed < limit);
        return labels[band < 0 ? labels.length - 1 : band];
    }

    // Compass labels and arrows both point toward the wind's source.
    function windBearing(degrees: var): string {
        if (typeof degrees !== "number" || !Number.isFinite(degrees) || degrees < 0 || degrees > 360)
            return "";
        return ["N ↑", "NE ↗", "E →", "SE ↘", "S ↓", "SW ↙", "W ←", "NW ↖"][Math.round(degrees / 45) % 8];
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

    // Restore before a popup can change a preference and overwrite the saved city.
    Component.onCompleted: saved.text()
    onFeelsLikeChanged: if (root.restored) saved.writeAdapter()

    FileView {
        id: saved
        path: Paths.state("weather.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            if (!root.location && stored.location?.name && Number.isFinite(stored.location.latitude) && Number.isFinite(stored.location.longitude))
                root.location = stored.location;
            root.restored = true;
        }
        onLoadFailed: root.restored = true
        JsonAdapter {
            id: stored
            property var location: null
            property bool feelsLike: false
        }
    }

    Timer {
        // Align the graph clock with minute boundaries, including city midnight.
        // The same tick renews a forecast past the helper's 15-minute cache by
        // the wall clock: Qt timers stand still while the machine sleeps, so a
        // 15-minute countdown kept a stale forecast up long after every wake.
        interval: Math.max(1, 60000 - Math.floor(root.now * 1000) % 60000)
        running: root.enabled
        repeat: true
        onTriggered: {
            root.now = Date.now() / 1000;
            if (!root.loading && root.now - root.updatedAt >= 15 * 60)
                root.refresh();
        }
    }
    // Wake at the helper's persisted deadline; manual refresh and reconnect
    // use the same gate and cannot shorten a provider's cooldown. Measured
    // from `now`, so a wake that comes early (Qt rounds long timers to whole
    // seconds) restarts for the remainder rather than a whole backoff again.
    Timer {
        id: retryWake
        interval: Math.max(1, Math.min(2147483647, Math.ceil((root.nextRetryAt - root.now) * 1000)))
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
    // Both timers above take their interval from `now`, so moving it after a
    // sleep restarts them on what is really left: a deadline that passed in
    // the night fires at once, and the minute tick renews a stale forecast.
    Connections {
        target: WallClock
        function onWokeUp(): void {
            root.now = Date.now() / 1000;
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

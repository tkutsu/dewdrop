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
    property string searchReply: ""
    property string forecastRequest: ""
    property string compareRequest: ""
    // Celsius for this hour by model, from the last comparison for this city.
    property var modelTemperatures: ({})
    readonly property bool loading: !!forecastJob.want && (forecastJob.running || forecastJob.arg !== forecastJob.want)
    // Process startup briefly looks idle; only an accepted reply finishes a search.
    readonly property bool searching: !!searchJob.want && root.searchReply !== searchJob.want
    readonly property bool stale: root.updatedAt > 0 && (root.now - root.updatedAt > 1800 || root.trouble !== "")

    // Not flatMap: Qt's JavaScript engine does not have it.
    readonly property var allHours: [].concat(...root.days.map(day => day.hours))
    readonly property var thisHour: root.allHours.find(hour => hour.at <= root.now && root.now < hour.at + 3600) ?? null
    readonly property var today: root.thisHour ? root.days.find(day => day.hours.includes(root.thisHour)) ?? null : null
    readonly property var upcoming: root.allHours.filter(hour => hour.at + 3600 > root.now && hour.at < root.now + 6 * 3600)
    // The hourly field behind every temperature shown, following Feels Like.
    readonly property string temperatureKey: root.feelsLike ? "feelsLike" : "temperature"
    readonly property string summary: root.summarize(root.upcoming)
    readonly property var outlook: root.upcoming.reduce((worst, hour) => !worst || hour.severity > worst.severity ? hour : worst, null)
    readonly property string icon: root.outlook?.icon ?? "\u{f0590}"
    readonly property string temperatureSymbol: Settings.weatherUnit === "fahrenheit" ? "°F" : Settings.weatherUnit === "kelvin" ? "K" : "°C"
    // Open-Meteo's global models with a full week of rain chances; the others
    // leave the popup's rain line blank.
    // `about`: who runs it and what it is good for, under the setting.
    readonly property var models: [
        { value: "best_match", label: "Auto", about: "Open-Meteo picks the sharpest model covering the place." },
        { value: "ecmwf_ifs", label: "ECMWF", about: "Europe's joint forecast centre, Reading. Global at 9 km; the reference for the week ahead." },
        { value: "icon_seamless", label: "DWD ICON", about: "Germany's weather service. Global, down to 7 km over Europe." },
        { value: "gfs_seamless", label: "NOAA GFS", about: "The US National Weather Service. Global, down to 3 km over the US." },
        { value: "ukmo_seamless", label: "UK Met Office", about: "The UK's weather service, Exeter. Global at 10 km, 2 km over the UK." },
        { value: "gem_seamless", label: "Canada GEM", about: "Environment Canada. Global at 15 km, 2.5 km over Canada." }
    ]
    readonly property string model: root.models.some(option => option.value === Settings.weatherModel) ? Settings.weatherModel : "best_match"
    readonly property string modelAbout: root.models.find(option => option.value === root.model).about
    // The models as settings lists them, each with its temperature now, to
    // hold against a thermometer nearby.
    readonly property var modelOptions: root.models.map(option => {
        const temperature = root.modelTemperatures[option.value];
        return { value: option.value, label: temperature == null ? option.label : `${option.label} · ${root.formatTemperature(temperature, false)}` };
    })
    // The popup's icons in the colour of their weather. Rain and wind share
    // the graph's hues for those series.
    readonly property var tints: ({
            "\u{f0599}": "#f5cf5f", // sun
            "\u{f0595}": "#eedb9e", // sun and cloud
            "\u{f0594}": "#d5dbf0", // moon
            "\u{f0f31}": "#bcc3da", // moon and cloud
            "\u{f0590}": "#a9afba", // overcast
            "\u{f0591}": "#bfc4c9", // fog
            "\u{f0597}": "#86b8f0", // rain
            "\u{f0596}": "#5f9cf2", // pouring
            "\u{f067f}": "#a3dcf2", // freezing rain
            "\u{f0598}": "#ffffff", // snow
            "\u{f067e}": "#c5a3f5", // thunderstorm
            "\u{f059d}": "#b4cfa0"  // wind
        })
    function tint(icon: string): color {
        return root.tints[icon] ?? Theme.fg;
    }
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
            const temperatures = hours.map(hour => hour[root.temperatureKey]).filter(finite);
            if (!temperatures.length)
                return "";
            const minimum = Math.min(...temperatures);
            const maximum = Math.max(...temperatures);
            const low = Math.round(minimum);
            const high = Math.round(maximum);
            const first = hours[0][root.temperatureKey];
            const last = hours[hours.length - 1][root.temperatureKey];
            if (maximum >= 35)
                return `Hot, up to ${root.formatTemperature(maximum, true)}`;
            if (minimum <= 0)
                return `Freezing, down to ${root.formatTemperature(minimum, true)}`;
            if (finite(first) && finite(last) && Math.abs(Math.round(last) - Math.round(first)) >= 3)
                return `${last > first ? "Warming" : "Cooling"} to ${root.formatTemperature(last, true)}`;
            return high - low <= 2 ? `Around ${root.formatTemperature((low + high) / 2, true)}` : `Around ${root.measure(root.temperatureValue(minimum), "")}-${root.formatTemperature(maximum, true)}`;
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
        if (!root.location)
            return;
        if (root.loading)
            return;
        retryWake.stop();
        // A retry must reach the provider even if a failed manual refresh left a fresh cache.
        root.forecastRequest = JSON.stringify([++root.revision, root.location.latitude, root.location.longitude, root.location.timezone || "auto", root.model, !!force || root.trouble !== ""]);
    }

    // At most once per ten minutes for a city: asking again within them
    // leaves the request as it was, so nothing runs.
    function compareModels(): void {
        if (root.location)
            root.compareRequest = JSON.stringify([root.location.latitude, root.location.longitude, root.location.timezone || "auto", Math.floor(Date.now() / 600000)]);
    }

    // Forecasts stay in Celsius so thresholds and graph geometry do not depend on display units.
    function temperatureValue(value: var): var {
        if (typeof value !== "number" || !Number.isFinite(value))
            return null;
        return Settings.weatherUnit === "fahrenheit" ? value * 9 / 5 + 32 : Settings.weatherUnit === "kelvin" ? value + 273.15 : value;
    }

    // Compact Celsius and Fahrenheit readouts share a degree sign; Kelvin never takes one.
    function formatTemperature(value: var, withUnit: bool): string {
        return root.measure(root.temperatureValue(value), root.temperatureSymbol === "K" ? " K" : withUnit ? root.temperatureSymbol : "°");
    }

    // A day's high and low. The forecast's daily figures are air temperatures,
    // so Feels Like reads them off the hours; a day without any shows as unknown.
    function highLow(day: var): string {
        const felt = day.hours.map(hour => hour.feelsLike).filter(value => typeof value === "number");
        const [high, low] = root.feelsLike ? [Math.max(...felt), Math.min(...felt)] : [day.high, day.low];
        return `${root.formatTemperature(high, false)} / ${root.formatTemperature(low, false)}`;
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

    // A new city or model drops the old forecast before fetching.
    function startOver(): void {
        root.days = [];
        root.updatedAt = 0;
        root.trouble = "";
        root.forecastRequest = "";
        root.refresh();
    }
    onLocationChanged: {
        root.modelTemperatures = {};
        root.compareRequest = "";
        root.startOver();
    }
    onModelChanged: root.startOver()
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
        running: true
        repeat: true
        onTriggered: {
            root.now = Date.now() / 1000;
            if (!root.loading && !retryWake.running && root.now - root.updatedAt >= 15 * 60)
                root.refresh();
        }
    }
    // Retry failed forecasts once per delay; manual refresh can try sooner.
    Timer {
        id: retryWake
        interval: 30000
        onTriggered: root.refresh()
    }
    Connections {
        target: WallClock
        function onWokeUp(): void {
            root.now = Date.now() / 1000;
            if (root.trouble || root.now - root.updatedAt >= 15 * 60)
                root.refresh();
            if (root.searchTrouble)
                root.searchRevision++;
        }
    }
    Connections {
        target: Network
        function onOnlineChanged(): void {
            if (!Network.online)
                return;
            if (root.trouble)
                root.refresh();
            if (root.searchTrouble)
                root.searchRevision++;
        }
    }

    QueuedProcess {
        id: forecastJob
        want: root.forecastRequest
        command: {
            if (!arg)
                return [];
            const request = JSON.parse(arg);
            return ["python3", Quickshell.shellPath("scripts/weather-fetch.py"), "forecast", String(request[1]), String(request[2]), request[3], request[4], "--cache", Paths.cache("weather-forecast.json"), ...(request[5] ? ["--force"] : [])];
        }
        onResult: (request, output) => {
            const relevant = request === root.forecastRequest;
            let result;
            try { result = JSON.parse(output); } catch (e) { result = {error: "Could not read the weather forecast."}; }
            root.now = Date.now() / 1000;
            if (!relevant)
                return;
            if (result.days?.length) {
                root.days = result.days;
                root.updatedAt = result.fetchedAt ?? root.now;
            }
            if (result.error || !result.days?.length) {
                root.trouble = result.error || "The forecast is unavailable.";
                retryWake.restart();
                return;
            }
            retryWake.stop();
            root.trouble = "";
        }
    }

    QueuedProcess {
        id: compareJob
        want: root.compareRequest
        command: {
            if (!arg)
                return [];
            const request = JSON.parse(arg);
            return ["python3", Quickshell.shellPath("scripts/weather-fetch.py"), "compare", String(request[0]), String(request[1]), request[2], ...root.models.map(option => option.value), "--cache", Paths.cache("weather-forecast.json")];
        }
        onResult: (request, output) => {
            let result;
            try { result = JSON.parse(output); } catch (e) { result = {}; }
            if (request !== root.compareRequest)
                return;
            // A failed comparison keeps the labels plain; opening settings again asks again.
            if (!result.temperatures)
                root.compareRequest = "";
            else
                root.modelTemperatures = result.temperatures;
        }
    }

    QueuedProcess {
        id: searchJob
        interval: 350
        want: root.query.trim().length >= 2 ? JSON.stringify([root.searchRevision, root.query.trim()]) : ""
        command: ["python3", Quickshell.shellPath("scripts/weather-fetch.py"), "search", arg ? JSON.parse(arg)[1] : "", "--cache", Paths.cache("weather-forecast.json")]
        onResult: (request, output) => {
            const relevant = request === want;
            let result;
            try { result = JSON.parse(output); } catch (e) { result = {error: "Could not read the location results."}; }
            root.now = Date.now() / 1000;
            if (!relevant)
                return;
            root.locations = result.locations ?? [];
            root.searchTrouble = result.error ?? (root.locations.length === 0 ? "No matching locations." : "");
            root.searchReply = request;
        }
    }
}

#!/usr/bin/env python3
"""Read Open-Meteo and return display-ready forecasts in the city's timezone."""

import argparse
import json
import math
import os
import tempfile
import time
from collections import Counter
from datetime import datetime
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import urlopen
from zoneinfo import ZoneInfo


# km/h, where the six-hour summary starts saying "Strong winds".
WINDY = 39
# Refetch forecasts cached before the thick-fog display threshold.
CACHE_VERSION = 3


def condition(code, daylight=True):
    """Map WMO conditions to the Material Design glyphs used by the bar."""
    if code == 0:
        return ("Clear", "\U000f0599" if daylight else "\U000f0594", 0)
    if code in (1, 2):
        return ("Partly cloudy", "\U000f0595" if daylight else "\U000f0f31", 1)
    if code == 3:
        return ("Overcast", "\U000f0590", 2)
    if code in (45, 48):
        return ("Fog", "\U000f0591", 3)
    if code in (51, 53, 55):
        return ("Drizzle", "\U000f0597", 4)
    if code in (56, 57, 66, 67):
        return ("Freezing rain", "\U000f067f", 7)
    if code in (61, 63, 65, 80, 81, 82):
        return ("Heavy rain" if code in (65, 82) else "Rain", "\U000f0596" if code in (65, 82) else "\U000f0597", 6 if code in (65, 82) else 5)
    if code in (71, 73, 75, 77, 85, 86):
        return ("Snow", "\U000f0598", 7)
    if code in (95, 96, 99):
        return ("Thunderstorm", "\U000f067e", 8)
    return ("Unavailable", "\U000f0590", -1)


def number(value):
    """Keep missing measurements null rather than displaying them as zero."""
    return value if isinstance(value, (int, float)) and math.isfinite(value) else None


def visible_code(code, visibility, cloud_cover):
    """Show only provider-confirmed thick fog, with visibility below 200 m."""
    if code not in (45, 48):
        return code
    if visibility is not None and 0 <= visibility < 200:
        return code
    # Thin or unverified fog gives way to the forecast sky condition.
    if cloud_cover is None or not 0 <= cloud_cover <= 100:
        return -1
    return 0 if cloud_cover <= 20 else 2 if cloud_cover <= 80 else 3


def day_conditions(hours):
    """Pair predominant daylight weather with the worst corrected hourly condition."""
    known = [hour for hour in hours if hour["severity"] >= 0]
    daylight = [hour for hour in known if hour["isDay"]] or known
    if not known:
        description, icon, _ = condition(-1)
        return {"description": description, "icon": icon, "severeDescription": description, "severeIcon": icon}
    counts = Counter(hour["description"] for hour in daylight)
    predominant = max(daylight, key=lambda hour: (counts[hour["description"]], hour["severity"]))
    severe = max(known, key=lambda hour: hour["severity"])
    return {
        "description": predominant["description"], "icon": condition(predominant["code"])[1],
        "severeDescription": severe["description"], "severeIcon": condition(severe["code"])[1],
    }


def normalize(body):
    """Group hourly epochs by local calendar date, including DST transitions."""
    zone = ZoneInfo(body["timezone"])
    hourly, daily = body["hourly"], body["daily"]
    visibilities = hourly.get("visibility", [None] * len(hourly["time"]))
    cloud_covers = hourly.get("cloud_cover", [None] * len(hourly["time"]))
    hours_by_day = {}
    for i, stamp in enumerate(hourly["time"]):
        local = datetime.fromtimestamp(stamp, zone)
        visibility = number(visibilities[i])
        if visibility is not None and visibility < 0:
            visibility = None
        cloud_cover = number(cloud_covers[i])
        code = visible_code(hourly["weather_code"][i], visibility, cloud_cover)
        is_day = hourly["is_day"][i] == 1
        description, icon, severity = condition(code, is_day)
        wind = number(hourly["wind_speed_10m"][i])
        # Strong wind outshows a dry sky; the description and severity keep
        # the sky for the six-hour summary.
        if 0 <= severity <= 2 and wind is not None and wind >= WINDY:
            icon = "\U000f059d"
        hours_by_day.setdefault(local.date().isoformat(), []).append({
            "at": stamp, "time": local.strftime("%H:%M"),
            "temperature": number(hourly["temperature_2m"][i]),
            "feelsLike": number(hourly["apparent_temperature"][i]),
            "rain": number(hourly["precipitation_probability"][i]),
            "wind": wind,
            "windDirection": number(hourly["wind_direction_10m"][i]),
            "code": code, "isDay": is_day, "visibility": visibility,
            "description": description, "icon": icon, "severity": severity,
        })
    days = []
    for i, stamp in enumerate(daily["time"]):
        local = datetime.fromtimestamp(stamp, zone)
        date = local.date().isoformat()
        hours = hours_by_day.get(date, [])
        days.append({
            "date": date, "weekday": local.strftime("%a"), **day_conditions(hours),
            "high": number(daily["temperature_2m_max"][i]),
            "low": number(daily["temperature_2m_min"][i]),
            "rain": number(daily["precipitation_probability_max"][i]),
            "hours": hours,
        })
    if len(days) != 7 or not all(day["hours"] for day in days):
        raise ValueError("Incomplete forecast")
    return {"days": days}


def fetch(mode, args):
    """Fetch public JSON over HTTPS with a bounded network wait."""
    if mode == "search":
        base = "https://geocoding-api.open-meteo.com/v1/search"
        params = {"name": args[0], "count": 5, "language": "en", "format": "json"}
    elif mode == "forecast":
        lat, lon = float(args[0]), float(args[1])
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            raise ValueError("Invalid coordinates")
        base = "https://api.open-meteo.com/v1/forecast"
        params = {
            "latitude": lat, "longitude": lon, "timezone": args[2], "timeformat": "unixtime", "forecast_days": 7,
            "hourly": "temperature_2m,apparent_temperature,weather_code,precipitation_probability,wind_speed_10m,wind_direction_10m,is_day,visibility,cloud_cover",
            "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
        }
    else:
        raise ValueError("Unknown request")
    with urlopen(base + "?" + urlencode(params), timeout=15) as response:
        body = json.load(response)
    if mode == "forecast":
        return normalize(body)
    return {"locations": [{
        "name": place["name"], "label": ", ".join(dict.fromkeys(filter(None, [place["name"], place.get("admin1"), place.get("country")]))),
        "latitude": place["latitude"], "longitude": place["longitude"], "timezone": place.get("timezone", "auto"),
    } for place in body.get("results", [])]}


def read_json(path):
    """Missing or damaged local JSON does not prevent fetching weather."""
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def write_json(path, value):
    """Replace one complete JSON file, keeping readers away from partial writes."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=path.name + ".", delete=False) as output:
        temporary = Path(output.name)
        try:
            json.dump(value, output, ensure_ascii=False)
            output.flush()
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def request(mode, args, cache_path, force=False):
    """Reuse fresh forecasts and preserve the last forecast when fetching fails."""
    cache_path = Path(cache_path)
    now = time.time()
    snapshot = {}
    if mode == "forecast":
        key = [float(args[0]), float(args[1]), args[2]]
        cached = read_json(cache_path)
        forecast = cached.get("forecast", {})
        if cached.get("key") == key and len(forecast.get("days", [])) == 7 and number(cached.get("fetchedAt")) is not None:
            snapshot = {**forecast, "fetchedAt": cached["fetchedAt"], "cached": True}
        if snapshot and cached.get("version") == CACHE_VERSION and not force and 0 <= now - snapshot["fetchedAt"] < 15 * 60:
            return snapshot

    try:
        result = fetch(mode, args)
    except Exception as error:
        if isinstance(error, HTTPError):
            error.close()
        reason = "Check your connection and try again." if isinstance(error, OSError) else "The forecast it sent could not be read."
        return {**snapshot, "error": f"Weather request failed. {reason}"}

    if mode == "forecast":
        result = {**result, "fetchedAt": time.time()}
        write_json(cache_path, {"version": CACHE_VERSION, "key": key, "forecast": result, "fetchedAt": result["fetchedAt"]})
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["forecast", "search"])
    parser.add_argument("args", nargs="+")
    parser.add_argument("--cache", required=True)
    parser.add_argument("--force", action="store_true")
    options = parser.parse_args()
    try:
        result = request(options.mode, options.args, options.cache, options.force)
    except Exception:
        # One JSON result even on failure, so the UI can always end loading.
        result = {"error": "Could not load weather or save its forecast."}
    print(json.dumps(result, ensure_ascii=False))

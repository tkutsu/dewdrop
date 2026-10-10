#!/usr/bin/env python3
"""Read Open-Meteo and return display-ready forecasts in the city's timezone."""

import argparse
import fcntl
import json
import math
import os
import tempfile
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import urlopen
from zoneinfo import ZoneInfo


# km/h, where the six-hour summary starts saying "Strong winds".
WINDY = 39


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


def normalize(body):
    """Group hourly epochs by local calendar date, including DST transitions."""
    zone = ZoneInfo(body["timezone"])
    hourly, daily = body["hourly"], body["daily"]
    hours_by_day = {}
    for i, stamp in enumerate(hourly["time"]):
        local = datetime.fromtimestamp(stamp, zone)
        code = hourly["weather_code"][i]
        description, icon, severity = condition(code, hourly["is_day"][i] == 1)
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
            "description": description, "icon": icon, "severity": severity,
        })
    days = []
    for i, stamp in enumerate(daily["time"]):
        local = datetime.fromtimestamp(stamp, zone)
        date = local.date().isoformat()
        days.append({
            "date": date, "weekday": local.strftime("%a"), "icon": condition(daily["weather_code"][i])[1],
            "high": number(daily["temperature_2m_max"][i]),
            "low": number(daily["temperature_2m_min"][i]),
            "rain": number(daily["precipitation_probability_max"][i]),
            "hours": hours_by_day.get(date, []),
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
            "hourly": "temperature_2m,apparent_temperature,weather_code,precipitation_probability,wind_speed_10m,wind_direction_10m,is_day",
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


def retry_after(header, now, fallback):
    """Accept Retry-After as delay seconds or an HTTP date."""
    if header is not None:
        text = header.strip()
        if text.isascii() and text.isdigit() and int(text) > 0:
            return now + int(text)
        try:
            date = parsedate_to_datetime(text)
            if date.tzinfo is None:
                date = date.replace(tzinfo=timezone.utc)
            if date.timestamp() > now:
                return date.timestamp()
        except (TypeError, ValueError, OverflowError):
            pass
    return now + fallback


def request(mode, args, state_path, cache_path, force=False):
    """Share cached forecasts and persisted backoff across workers and reloads."""
    state_path, cache_path = Path(state_path), Path(cache_path)
    state_path.parent.mkdir(parents=True, exist_ok=True)
    # Hold the lock through the fetch: a worker from a reload must observe
    # the first worker's cache or cooldown before making another request.
    with state_path.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        now = time.time()
        state = read_json(state_path)
        snapshot = {}
        if mode == "forecast":
            key = [float(args[0]), float(args[1]), args[2]]
            cached = read_json(cache_path)
            forecast = cached.get("forecast", {})
            if cached.get("key") == key and len(forecast.get("days", [])) == 7 and number(cached.get("fetchedAt")) is not None:
                snapshot = {**forecast, "fetchedAt": cached["fetchedAt"], "cached": True}

        cooldown = state.get("cooldownUntil", 0)
        if cooldown > now:
            return {**snapshot, "error": "Weather is rate limited. Waiting for the cooldown to end.", "status": 429, "cooldownUntil": cooldown, "retryAt": cooldown}
        retry_at = state.get("forecastRetryAt", 0) if mode == "forecast" else 0
        if retry_at > now:
            return {**snapshot, "error": "Weather request failed. Waiting before trying again.", "retryAt": retry_at}
        if snapshot and not force and 0 <= now - snapshot["fetchedAt"] < 15 * 60:
            return snapshot

        try:
            result = fetch(mode, args)
        except Exception as error:
            now = time.time()
            if isinstance(error, HTTPError) and error.code == 429:
                attempts = min(state.get("rateFailures", 0) + 1, 8)
                cooldown = retry_after(error.headers.get("Retry-After"), now, min(15 * 60 * 2 ** (attempts - 1), 24 * 3600))
                error.close()
                state.update(cooldownUntil=cooldown, rateFailures=attempts)
                write_json(state_path, state)
                return {**snapshot, "error": "Weather is rate limited. Waiting for the cooldown to end.", "status": 429, "cooldownUntil": cooldown, "retryAt": cooldown}
            if isinstance(error, HTTPError):
                error.close()
            # Transport and HTTP failures are OSErrors; anything else is a
            # reply that could not be read, which no reconnecting will fix.
            reason = "Check your connection and try again." if isinstance(error, OSError) else "The forecast it sent could not be read."
            result = {**snapshot, "error": f"Weather request failed. {reason}"}
            if mode == "forecast":
                attempts = min(state.get("forecastFailures", 0) + 1, 5)
                result["retryAt"] = now + min(30 * 2 ** (attempts - 1), 300)
                state.update(forecastRetryAt=result["retryAt"], forecastFailures=attempts)
                write_json(state_path, state)
            return result

        state.update(cooldownUntil=0, rateFailures=0)
        if mode == "forecast":
            result = {**result, "fetchedAt": time.time()}
            write_json(cache_path, {"key": key, "forecast": result, "fetchedAt": result["fetchedAt"]})
            state.update(forecastRetryAt=0, forecastFailures=0)
        write_json(state_path, state)
        return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["forecast", "search"])
    parser.add_argument("args", nargs="+")
    parser.add_argument("--state", required=True)
    parser.add_argument("--cache", required=True)
    parser.add_argument("--force", action="store_true")
    options = parser.parse_args()
    try:
        result = request(options.mode, options.args, options.state, options.cache, options.force)
    except Exception:
        # One JSON result even on failure, so the UI can always end loading.
        result = {"error": "Could not load weather or save its request state.", "retryAt": time.time() + 30}
    print(json.dumps(result, ensure_ascii=False))

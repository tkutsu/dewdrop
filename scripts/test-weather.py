#!/usr/bin/env python3
"""Check weather caching and failures without making network requests."""

import importlib.util
import io
import json
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlsplit

spec = importlib.util.spec_from_file_location("weather", Path(__file__).with_name("weather-fetch.py"))
weather = importlib.util.module_from_spec(spec)
spec.loader.exec_module(weather)


class WeatherRequests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="weather-requests-test-")
        self.addCleanup(self.directory.cleanup)
        self.cache = Path(self.directory.name) / "forecast.json"
        clock_patch = patch.object(weather.time, "time", return_value=10000)
        self.clock = clock_patch.start()
        self.addCleanup(clock_patch.stop)
        self.forecast = {"days": [{"date": "2026-10-03", "hours": [{"at": 10000, "feelsLike": 18}]}] * 7}

    def request(self, mode="forecast", args=None, force=False):
        return weather.request(mode, args or ["37.98", "23.73", "Europe/Athens"], self.cache, force)

    def rate_limit(self, header=None):
        return HTTPError("https://api.open-meteo.com/", 429, "Too Many Requests", {"Retry-After": header} if header is not None else {}, None)

    def test_fresh_cache_survives_helper_restart(self):
        with patch.object(weather, "fetch", return_value=self.forecast) as fetch:
            first = self.request()
            self.assertEqual(first["fetchedAt"], 10000)
            self.assertEqual(self.request()["fetchedAt"], first["fetchedAt"])
            self.assertEqual(fetch.call_count, 1)
        self.clock.return_value += 901
        with patch.object(weather, "fetch", return_value=self.forecast) as fetch:
            self.request()
            fetch.assert_called_once()

    def test_cache_does_not_cross_locations_and_manual_refresh_can_update(self):
        with patch.object(weather, "fetch", return_value=self.forecast) as fetch:
            self.request()
            self.request(force=True)
            self.request(args=["40", "20", "Europe/Athens"])
            self.assertEqual(fetch.call_count, 3)

    def test_fresh_legacy_forecast_is_refetched_for_visibility_and_daily_icons(self):
        weather.write_json(self.cache, {"key": [37.98, 23.73, "Europe/Athens"],
                                       "forecast": self.forecast, "fetchedAt": 10000})
        with patch.object(weather, "fetch", return_value=self.forecast) as fetch:
            self.request()
            self.request()
            fetch.assert_called_once()
        self.assertEqual(weather.read_json(self.cache)["version"], weather.CACHE_VERSION)

    def test_older_cache_is_updated_and_preserved_on_failure(self):
        old = {"days": [{"date": "2026-10-03", "hours": [{"at": 10000}]}] * 7}
        cached = {"key": [37.98, 23.73, "Europe/Athens"], "forecast": old, "fetchedAt": 10000}
        weather.write_json(self.cache, cached)
        self.clock.return_value += 901
        with patch.object(weather, "fetch", return_value=self.forecast) as fetch:
            upgraded = self.request()
            self.request()
            fetch.assert_called_once()
            self.assertEqual(upgraded["days"][0]["hours"][0]["feelsLike"], 18)

        weather.write_json(self.cache, cached)
        with patch.object(weather, "fetch", side_effect=URLError("offline")):
            failed = self.request()
            self.assertEqual(failed["days"], old["days"])
            self.assertEqual(failed["fetchedAt"], 10000)
            self.assertEqual(weather.read_json(self.cache), cached)

    def test_rate_limit_is_a_failure_without_persisted_request_gates(self):
        with patch.object(weather, "fetch", side_effect=self.rate_limit("600")) as fetch:
            failed = self.request()
            self.assertIn("error", failed)
            self.assertNotIn("retryAt", failed)
            self.assertNotIn("cooldownUntil", failed)
            self.request(force=True)
            self.request("search", ["Athens"])
            self.assertEqual(fetch.call_count, 3)
        self.assertEqual(list(Path(self.directory.name).iterdir()), [])

    def test_failures_do_not_prevent_a_later_success(self):
        with patch.object(weather, "fetch", side_effect=URLError("offline")):
            self.assertIn("connection", self.request()["error"])
        with patch.object(weather, "fetch", return_value=self.forecast):
            self.assertEqual(self.request()["days"], self.forecast["days"])

    def test_unreadable_reply_is_not_blamed_on_the_connection(self):
        with patch.object(weather, "fetch", side_effect=ValueError("Incomplete forecast")):
            self.assertIn("could not be read", self.request()["error"])

    def test_failed_other_city_never_returns_previous_city_cache(self):
        with patch.object(weather, "fetch", return_value=self.forecast):
            self.request()
        with patch.object(weather, "fetch", side_effect=URLError("offline")):
            self.assertNotIn("days", self.request(args=["40", "20", "Europe/Athens"]))

    def test_damaged_or_future_cache_does_not_block_fetch(self):
        for contents in ["broken", "[]", json.dumps({"key": [37.98, 23.73, "Europe/Athens"],
                "forecast": self.forecast, "fetchedAt": 11000})]:
            with self.subTest(contents=contents):
                self.cache.write_text(contents)
                with patch.object(weather, "fetch", return_value=self.forecast) as fetch:
                    self.request()
                    fetch.assert_called_once()

    def test_search_preserves_normalized_results(self):
        expected = {"locations": [{"name": "Athens", "latitude": 37.98}]}
        with patch.object(weather, "fetch", return_value=expected):
            self.assertEqual(self.request("search", ["Athens"]), expected)


class WeatherTemperatures(unittest.TestCase):
    def setUp(self):
        days = [1790985600 + i * 86400 for i in range(7)]
        self.body = {
            "timezone": "UTC",
            "utc_offset_seconds": 0,
            "hourly": {
                "time": days,
                "temperature_2m": [20] * 7,
                "apparent_temperature": [17, None, -3, 0, 18, 19, 20],
                "weather_code": [0] * 7,
                "is_day": [1] * 7,
                "precipitation_probability": [0] * 7,
                "wind_speed_10m": [15] * 7,
                "wind_direction_10m": [0, None, 90, 180, 270, 360, 45],
            },
            "daily": {
                "time": days,
                "weather_code": [0] * 7,
                "temperature_2m_max": [25] * 7,
                "temperature_2m_min": [15] * 7,
                "precipitation_probability_max": [0] * 7,
            },
        }

    def test_normalizes_air_and_feels_like_temperatures_including_missing_values(self):
        forecast = weather.normalize(self.body)
        self.assertEqual(set(forecast), {"days"})
        days = forecast["days"]
        self.assertEqual(days[0]["hours"][0]["temperature"], 20)
        self.assertEqual(days[0]["hours"][0]["feelsLike"], 17)
        self.assertEqual((days[0]["high"], days[0]["low"]), (25, 15))
        self.assertIsNone(days[1]["hours"][0]["feelsLike"])
        self.assertEqual(days[2]["hours"][0]["feelsLike"], -3)
        self.assertEqual(days[3]["hours"][0]["feelsLike"], 0)

    def test_forecast_requests_hourly_feels_like_fields(self):
        with patch.object(weather, "urlopen", return_value=io.StringIO(json.dumps(self.body))) as opened:
            forecast = weather.fetch("forecast", ["37.98", "23.73", "Europe/Athens"])
        params = parse_qs(urlsplit(opened.call_args.args[0]).query)
        self.assertIn("apparent_temperature", params["hourly"][0].split(","))
        self.assertNotIn("apparent_temperature_max", params["daily"][0].split(","))
        self.assertNotIn("apparent_temperature_min", params["daily"][0].split(","))
        self.assertEqual(forecast["days"][0]["hours"][0]["feelsLike"], 17)

    def test_normalizes_wind_direction_without_losing_north_or_missing_values(self):
        days = weather.normalize(self.body)["days"]
        self.assertEqual(days[0]["hours"][0]["windDirection"], 0)
        self.assertIsNone(days[1]["hours"][0]["windDirection"])
        self.assertEqual(days[3]["hours"][0]["windDirection"], 180)

    def test_strong_wind_shows_on_dry_hours_only(self):
        self.body["hourly"]["wind_speed_10m"] = [38, 39, 45, 45, None, 15, 15]
        self.body["hourly"]["weather_code"] = [0, 0, 3, 61, 0, 0, 0]
        hours = [day["hours"][0] for day in weather.normalize(self.body)["days"]]
        self.assertEqual([hour["icon"] for hour in hours[:5]], ["\U000f0599", "\U000f059d", "\U000f059d", "\U000f0597", "\U000f0599"])
        self.assertEqual((hours[1]["description"], hours[1]["severity"]), ("Clear", 0))

    def test_forecast_requests_hourly_wind_direction(self):
        with patch.object(weather, "urlopen", return_value=io.StringIO(json.dumps(self.body))) as opened:
            weather.fetch("forecast", ["37.98", "23.73", "Europe/Athens"])
        params = parse_qs(urlsplit(opened.call_args.args[0]).query)
        self.assertIn("wind_direction_10m", params["hourly"][0].split(","))

    def test_fog_requires_provider_fog_and_visibility_below_200_metres(self):
        self.body["hourly"]["weather_code"] = [45, 45, 48, 45, 45, 0, 61]
        self.body["hourly"]["visibility"] = [199, 200, 999, None, -1, 100, 100]
        self.body["hourly"]["cloud_cover"] = [100, 100, 20, 60, 100, 100, 100]
        hours = [day["hours"][0] for day in weather.normalize(self.body)["days"]]
        self.assertEqual([hour["description"] for hour in hours],
                         ["Fog", "Overcast", "Clear", "Partly cloudy", "Overcast", "Clear", "Rain"])
        self.assertEqual(hours[2]["visibility"], 999)
        self.assertIsNone(hours[4]["visibility"])
        self.assertEqual(weather.normalize(self.body)["days"][2]["severeDescription"], "Clear")

    def test_thick_fog_includes_zero_visibility_and_rime_fog(self):
        self.body["hourly"]["weather_code"] = [45, 48, 48, 45, 48, 45, 45]
        self.body["hourly"]["visibility"] = [0, 0, 199, 200, 200, 1000, float("nan")]
        self.body["hourly"]["cloud_cover"] = [100] * 7
        days = weather.normalize(self.body)["days"]
        self.assertEqual([day["hours"][0]["description"] for day in days],
                         ["Fog", "Fog", "Fog", "Overcast", "Overcast", "Overcast", "Overcast"])
        self.assertEqual([day["severeDescription"] for day in days],
                         ["Fog", "Fog", "Fog", "Overcast", "Overcast", "Overcast", "Overcast"])

    def test_unverified_fog_without_cloud_cover_is_unavailable(self):
        self.body["hourly"]["weather_code"][0] = 45
        hour = weather.normalize(self.body)["days"][0]["hours"][0]
        self.assertEqual(hour["description"], "Unavailable")

    def test_forecast_requests_visibility_and_cloud_cover(self):
        with patch.object(weather, "urlopen", return_value=io.StringIO(json.dumps(self.body))) as opened:
            weather.fetch("forecast", ["37.98", "23.73", "Europe/Athens"])
        fields = parse_qs(urlsplit(opened.call_args.args[0]).query)["hourly"][0].split(",")
        self.assertIn("visibility", fields)
        self.assertIn("cloud_cover", fields)

    def full_days(self):
        """Expand the seven-day fixture so daily summaries see day and night."""
        for key, values in self.body["hourly"].items():
            self.body["hourly"][key] = [value + hour * 3600 if key == "time" else
                                      int(7 <= hour < 19) if key == "is_day" else value
                                      for value in values for hour in range(24)]

    def test_daily_dates_stay_unique_across_clock_changes(self):
        for zone, start_date, changed_date, count in [
            ("Europe/Athens", "2026-10-22", "2026-10-25", 25),
            ("Europe/Athens", "2026-03-26", "2026-03-29", 23),
            ("America/New_York", "2026-10-29", "2026-11-01", 25),
            ("America/New_York", "2026-03-05", "2026-03-08", 23),
        ]:
            with self.subTest(zone=zone, start=start_date):
                start = datetime.fromisoformat(start_date).replace(tzinfo=weather.ZoneInfo(zone))
                first = int(start.timestamp())
                body = {
                    **self.body, "timezone": zone,
                    "utc_offset_seconds": int(start.utcoffset().total_seconds()),
                    "hourly": {
                        key: [first + i * 3600 for i in range(168)] if key == "time" else [values[0]] * 168
                        for key, values in self.body["hourly"].items()
                    },
                    "daily": {
                        **self.body["daily"],
                        "time": [first + i * 86400 for i in range(7)],
                        "temperature_2m_max": list(range(20, 27)),
                    },
                }
                days = weather.normalize(body)["days"]
                dates = [start + timedelta(days=i) for i in range(7)]
                self.assertEqual([day["date"] for day in days], [date.date().isoformat() for date in dates])
                self.assertEqual([day["weekday"] for day in days], [date.strftime("%a") for date in dates])
                self.assertEqual([day["high"] for day in days], list(range(20, 27)))
                changed = next(day for day in days if day["date"] == changed_date)
                self.assertEqual(len(changed["hours"]), count)
                for day in days:
                    for hour in day["hours"]:
                        self.assertEqual(datetime.fromtimestamp(hour["at"], start.tzinfo).date().isoformat(), day["date"])

    def test_daily_icons_pair_predominant_daylight_with_worst_full_day(self):
        self.full_days()
        # An overnight rain hour is significant, while daylight stays clear.
        self.body["hourly"]["weather_code"][23] = 61
        self.body["daily"]["weather_code"][0] = 45  # Must not bypass corrected hours.
        day = weather.normalize(self.body)["days"][0]
        self.assertEqual((day["description"], day["severeDescription"]), ("Clear", "Rain"))
        self.assertEqual((day["icon"], day["severeIcon"]),
                         (weather.condition(0)[1], weather.condition(61)[1]))

    def test_daily_predominance_ignores_night_and_handles_no_daylight(self):
        self.full_days()
        self.body["hourly"]["weather_code"][:24] = [3] * 7 + [0] * 12 + [3] * 5
        self.body["hourly"]["is_day"][24:48] = [0] * 24
        self.body["hourly"]["weather_code"][24:48] = [2] * 24
        days = weather.normalize(self.body)["days"]
        self.assertEqual((days[0]["description"], days[0]["severeDescription"]), ("Clear", "Overcast"))
        self.assertEqual(days[1]["icon"], weather.condition(2)[1])
        self.assertEqual(days[1]["icon"], days[1]["severeIcon"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

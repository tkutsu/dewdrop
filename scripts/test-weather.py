#!/usr/bin/env python3
"""Check weather caching and failures without making network requests."""

import importlib.util
import io
import json
import tempfile
import unittest
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


if __name__ == "__main__":
    unittest.main(verbosity=2)

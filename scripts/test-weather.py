#!/usr/bin/env python3
"""Check weather caching and rate limits without making network requests."""

import importlib.util
import io
import json
import tempfile
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from email.utils import formatdate
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
        self.state = Path(self.directory.name) / "state.json"
        self.cache = Path(self.directory.name) / "forecast.json"
        clock_patch = patch.object(weather.time, "time", return_value=10000)
        self.clock = clock_patch.start()
        self.addCleanup(clock_patch.stop)
        self.forecast = {"days": [{"date": "2026-10-03", "hours": [{"at": 10000, "feelsLike": 18}]}] * 7}

    def request(self, mode="forecast", args=None, force=False):
        return weather.request(mode, args or ["37.98", "23.73", "Europe/Athens"], self.state, self.cache, force)

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

    def test_older_cache_expires_and_remains_available_during_backoff(self):
        old = {"days": [{"date": "2026-10-03", "hours": [{"at": 10000}]}] * 7}
        cached = {"key": [37.98, 23.73, "Europe/Athens"], "forecast": old, "fetchedAt": 10000}
        weather.write_json(self.cache, cached)
        with patch.object(weather, "fetch", return_value=self.forecast) as fetch:
            self.clock.return_value += 901
            upgraded = self.request()
            self.request()
            fetch.assert_called_once()
            self.assertEqual(upgraded["days"][0]["hours"][0]["feelsLike"], 18)

        weather.write_json(self.cache, cached)
        with patch.object(weather, "fetch", side_effect=self.rate_limit("600")) as fetch:
            limited = self.request(force=True)
            restored = self.request(force=True)
            fetch.assert_called_once()
            self.assertEqual(restored["days"], old["days"])
            self.assertEqual(restored["cooldownUntil"], limited["cooldownUntil"])

    def test_numeric_retry_after_blocks_all_requests_including_manual_refresh(self):
        with patch.object(weather, "fetch", side_effect=self.rate_limit("600")) as fetch:
            result = self.request()
            self.assertEqual(result["status"], 429)
            self.assertEqual(result["cooldownUntil"], 10600)
            self.request(force=True)
            self.request("search", ["Athens"])
            self.request(args=["40", "20", "Europe/Athens"])
            self.assertEqual(fetch.call_count, 1)
        self.clock.return_value = 10600
        with patch.object(weather, "fetch", return_value=self.forecast) as fetch:
            self.request()
            fetch.assert_called_once()

    def test_http_date_retry_after(self):
        with patch.object(weather, "fetch", side_effect=self.rate_limit(formatdate(13600, usegmt=True))):
            self.assertEqual(self.request()["cooldownUntil"], 13600)

    def test_zero_or_expired_retry_after_cannot_create_a_tight_retry_loop(self):
        for header in ["0", formatdate(9000, usegmt=True)]:
            with self.subTest(header=header):
                self.state.unlink(missing_ok=True)
                with patch.object(weather, "fetch", side_effect=self.rate_limit(header)) as fetch:
                    self.assertEqual(self.request()["cooldownUntil"], 10900)
                    self.request(force=True)
                    self.assertEqual(fetch.call_count, 1)

    def test_missing_or_invalid_header_uses_increasing_persisted_cooldown(self):
        for header in [None, "invalid", "-20"]:
            with self.subTest(header=header):
                self.state.unlink(missing_ok=True)
                self.clock.return_value = 10000
                with patch.object(weather, "fetch", side_effect=self.rate_limit(header)) as fetch:
                    self.assertEqual(self.request()["cooldownUntil"], 10900)
                    self.request(force=True)
                    self.assertEqual(fetch.call_count, 1)
                    self.clock.return_value = 10900
                    self.assertEqual(self.request()["cooldownUntil"], 12700)

    def test_stale_forecast_is_preserved_during_cooldown(self):
        with patch.object(weather, "fetch", return_value=self.forecast):
            self.request()
        self.clock.return_value += 901
        with patch.object(weather, "fetch", side_effect=self.rate_limit("3600")):
            failed = self.request()
        with patch.object(weather, "fetch") as fetch:
            restored = self.request()
            fetch.assert_not_called()
            self.assertEqual(restored["days"], self.forecast["days"])
            self.assertEqual(restored["fetchedAt"], 10000)
            self.assertEqual(restored["cooldownUntil"], failed["cooldownUntil"])

    def test_transport_backoff_survives_reload_and_manual_refresh(self):
        with patch.object(weather, "fetch", side_effect=URLError("offline")) as fetch:
            self.assertEqual(self.request()["retryAt"], 10030)
            self.request(force=True)
            self.assertEqual(fetch.call_count, 1)
            self.clock.return_value = 10030
            self.assertEqual(self.request()["retryAt"], 10090)

    def test_unreadable_reply_is_not_blamed_on_the_connection(self):
        with patch.object(weather, "fetch", side_effect=URLError("offline")):
            self.assertIn("connection", self.request()["error"])
        self.state.unlink()
        with patch.object(weather, "fetch", side_effect=ValueError("Incomplete forecast")):
            result = self.request()
            self.assertIn("could not be read", result["error"])
            self.assertEqual(result["retryAt"], 10030)

    def test_search_rate_limit_also_blocks_forecasts(self):
        with patch.object(weather, "fetch", side_effect=self.rate_limit("120")) as fetch:
            self.request("search", ["Athens"])
            self.request()
            self.assertEqual(fetch.call_count, 1)

    def test_concurrent_reload_requests_share_one_fetch(self):
        def fetched(*args):
            time.sleep(0.05)
            return self.forecast
        with patch.object(weather, "fetch", side_effect=fetched) as fetch:
            with ThreadPoolExecutor(max_workers=2) as workers:
                results = list(workers.map(lambda _: self.request(), range(2)))
            self.assertEqual(fetch.call_count, 1)
            self.assertEqual(results[0]["fetchedAt"], results[1]["fetchedAt"])


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

    def test_forecast_requests_hourly_wind_direction(self):
        with patch.object(weather, "urlopen", return_value=io.StringIO(json.dumps(self.body))) as opened:
            weather.fetch("forecast", ["37.98", "23.73", "Europe/Athens"])
        params = parse_qs(urlsplit(opened.call_args.args[0]).query)
        self.assertIn("wind_direction_10m", params["hourly"][0].split(","))


if __name__ == "__main__":
    unittest.main(verbosity=2)

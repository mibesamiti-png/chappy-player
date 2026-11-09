"""Unit tests never read real network traffic or start a listener."""
from pathlib import Path
import json
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "examples" / "windows_companion"))
import pc_traffic_export as traffic  # noqa: E402
import companion  # noqa: E402


class TrafficExportTest(unittest.TestCase):
    def test_only_counter_deltas_no_identifiers(self):
        stream = iter([(1000 + i * 120, 2000 + i * 25)
                       for i in range(11)])
        delays = []
        report = traffic.capture(reader=lambda: next(stream),
                                 sleeper=delays.append)
        self.assertEqual(len(report["samples"]), 10)
        self.assertEqual(delays, [1.0] * 10)
        self.assertEqual(report["totals"], {"rx_bytes": 1200, "tx_bytes": 250})
        self.assertEqual(set(report), {"format", "source", "coverage",
                                       "interval_ms", "samples", "totals"})
        text = json.dumps(report)
        for private in ("hostname", "ip", "mac", "payload", "packet",
                        "cookie", "process", "username"):
            self.assertNotIn('"' + private + '"', text)

    def test_invalid_counters_and_reset_fail_closed(self):
        for n in (0, 4, 31, -1, True, "10"):
            with self.assertRaises(ValueError):
                traffic.capture(samples=n)
        with self.assertRaises(ValueError):
            traffic.capture(samples=5, reader=lambda: (-1, 2),
                            sleeper=lambda _: None)
        values = iter([(50, 90), (40, 90)])
        with self.assertRaises(ValueError):
            traffic.capture(samples=5, reader=lambda: next(values),
                            sleeper=lambda _: None)

    def test_export_is_new_only(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "pc.json"
            values = iter([(i * 10, i * 20) for i in range(6)])
            report = traffic.capture(samples=5, reader=lambda: next(values),
                                     sleeper=lambda _: None)
            traffic.write_report(report, out)
            original = out.read_bytes()
            self.assertEqual(json.loads(original)["totals"]["rx_bytes"], 50)
            with self.assertRaises(FileExistsError):
                traffic.write_report(report, out)
            self.assertEqual(out.read_bytes(), original)

    def test_cli_requires_explicit_approval_and_never_starts_network(self):
        self.assertEqual(companion.main([]), 0)
        self.assertEqual(companion.main(["--traffic-export", "--start"]), 2)
        self.assertEqual(companion.main(["--traffic-export", "--pair"]), 2)
        self.assertEqual(companion.main(["--traffic-export",
                                         "--traffic-seconds", "31"]), 2)
        with mock.patch("builtins.input", return_value="NO"), \
             mock.patch.object(traffic, "capture") as run:
            self.assertEqual(companion.main(["--traffic-export"]), 2)
            run.assert_not_called()
        with tempfile.TemporaryDirectory() as directory, \
             mock.patch("builtins.input", return_value="TRAFFIC"), \
             mock.patch.object(traffic, "capture",
                               return_value={"sample": "mock"}) as run:
            out = Path(directory) / "pc.json"
            self.assertEqual(companion.main([
                "--traffic-export", "--traffic-seconds", "5",
                "--traffic-out", str(out)]), 0)
            run.assert_called_once_with(samples=5)
            self.assertTrue(out.is_file())


if __name__ == "__main__":
    unittest.main()

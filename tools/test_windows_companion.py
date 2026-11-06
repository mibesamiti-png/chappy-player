"""Regression tests for the Windows opt-in, no-command DNS-SD companion."""

import ipaddress
import pathlib
import sys
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "examples" / "windows_companion"))

import companion  # noqa: E402


class NetworkBeaconTests(unittest.TestCase):
    def test_rfc1918_interface_only(self):
        for address in ("10.1.2.3", "172.17.0.1", "192.168.1.23"):
            self.assertEqual(companion.validate_lan_ipv4(address), address)
        for address in (
            "127.0.0.1", "169.254.1.2", "0.0.0.0", "::1",
            "8.8.8.8", "100.64.2.4", "192.0.2.1",
            "172.32.1.1", "example.com",
        ):
            with self.subTest(address=address), self.assertRaises(ValueError):
                companion.validate_lan_ipv4(address)

    def test_identity_changes_each_session_without_real_hostname(self):
        name, server = companion.service_identity("a1b2c3d4")
        self.assertEqual(name, "Chappy PC a1b2c3d4._workstation._tcp.local.")
        self.assertEqual(server, "chappy-a1b2c3d4.local.")
        for bad in ("", "INVALID", "a", "a" * 100):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                companion.service_identity(bad)

    def test_descriptor_declares_real_private_service_not_data_api(self):
        packet = companion.service_descriptor("192.168.1.7", 49152, "1234abcd")
        self.assertEqual(packet["type_"], "_workstation._tcp.local.")
        self.assertEqual(packet["addresses"], [bytes([192, 168, 1, 7])])
        self.assertEqual(packet["port"], 49152)
        self.assertEqual(packet["properties"][b"mode"], b"discovery-only")
        with self.assertRaises(ValueError):
            companion.service_descriptor("8.8.8.8", 49152, "1234abcd")
        with self.assertRaises(ValueError):
            companion.service_descriptor("192.168.1.7", 0, "1234abcd")

    def test_no_auto_start_and_explicit_start_only(self):
        with mock.patch.object(companion, "run_beacon") as start:
            self.assertEqual(companion.main([]), 0)
            self.assertEqual(companion.main(["--start", "--minutes", "0"]), 2)
            self.assertEqual(companion.main(["--start", "--minutes", "31"]), 2)
            start.assert_not_called()
        with (
            mock.patch.object(companion, "run_beacon") as start,
            mock.patch.object(
                companion, "discover_local_ipv4", return_value="192.168.1.7"
            ),
        ):
            self.assertEqual(companion.main(["--start", "--minutes", "3"]), 0)
            start.assert_called_once_with("192.168.1.7", 3)

    def test_unauthorized_public_ip_does_not_start(self):
        with mock.patch.object(companion, "run_beacon") as start:
            self.assertEqual(companion.main(["--start", "--ip", "8.8.8.8"]), 1)
            start.assert_not_called()

    def test_package_service_info_if_dependency_installed(self):
        try:
            from zeroconf import ServiceInfo
        except ImportError:
            self.skipTest("zeroconf dependency is Windows-preview only")
        info = ServiceInfo(
            **companion.service_descriptor("192.168.1.7", 49152, "a1b2c3d4")
        )
        self.assertEqual(info.port, 49152)
        self.assertEqual(info.name, "Chappy PC a1b2c3d4._workstation._tcp.local.")
        self.assertEqual(info.parsed_addresses(), ["192.168.1.7"])

    def test_safe_discovery_contract(self):
        text = (ROOT / "examples/windows_companion/companion.py").read_text()
        self.assertIn("zeroconf.unregister_service(info)", text)
        self.assertIn("zeroconf.close()", text)
        self.assertIn("listener.accept()", text)
        self.assertIn("connection.close()", text)
        self.assertNotIn("connection.recv(", text)
        self.assertNotIn("connection.send(", text)
        self.assertNotIn("subprocess.", text)
        self.assertNotIn("os.system(", text)
        self.assertNotIn("open(", text)
        self.assertNotIn("REMOTE_CONTROL", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)

"""PC Link R4 offline diagnostics and Windows launch safety regression tests."""
from __future__ import annotations

import contextlib
import io
import pathlib
import sys
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "examples" / "windows_companion"))
import companion  # noqa: E402
import pc_link_readiness as readiness  # noqa: E402


class ReadinessTests(unittest.TestCase):
    def probe(self, *, modules=(), identity="a" * 64,
              address="192.168.1.20", key_error=None, lan_error=None):
        lines = []
        def dependency(name):
            if name in modules:
                raise ImportError("sensitive dependency location")
            return object()
        def read_key():
            if key_error:
                raise key_error
            return identity
        def find_lan():
            if lan_error:
                raise lan_error
            return address
        ok = readiness.doctor(
            load_dependency=dependency, read_identity=read_key,
            find_lan=find_lan, report=lines.append,
        )
        return ok, "\n".join(lines)

    def test_success_does_not_print_sensitive_identity_or_address(self):
        ok, out = self.probe()
        self.assertTrue(ok)
        for code in ("PC-DOCTOR-READY", "PC-DOCTOR-DEPS-OK",
                     "PC-DOCTOR-KEY-OK", "PC-DOCTOR-LAN-OK"):
            self.assertIn(code, out)
        self.assertNotIn("a" * 64, out)
        self.assertNotIn("192.168.1.20", out)
        self.assertNotIn("hostname", out.lower())
        self.assertNotIn("private key", out.lower())

    def test_missing_key_fails_closed_with_explicit_create_guidance(self):
        ok, out = self.probe(identity=None)
        self.assertFalse(ok)
        self.assertIn("PC-DOCTOR-KEY:", out)
        self.assertIn("--identity-create", out)
        self.assertIn("PC-DOCTOR-NOT-READY", out)
        self.assertNotIn("PC-DOCTOR-READY:", out)

    def test_dependency_and_lan_failure_cannot_expose_raw_exception(self):
        ok, out = self.probe(
            modules=("qrcode",),
            key_error=OSError("private-user-path-123"),
            lan_error=RuntimeError("my-confidential-network"),
        )
        self.assertFalse(ok)
        self.assertIn("PC-DOCTOR-DEPS: qrcode", out)
        self.assertIn("PC-DOCTOR-KEY:", out)
        self.assertIn("PC-DOCTOR-LAN:", out)
        self.assertNotIn("private-user-path-123", out)
        self.assertNotIn("my-confidential-network", out)
        self.assertNotIn("sensitive dependency location", out)

    def test_public_and_invalid_network_addresses_fail_without_connect(self):
        for address in ("127.0.0.1", "8.8.8.8", "169.254.1.1",
                        "not an address", "::1"):
            with self.subTest(address=address):
                ok, out = self.probe(address=address)
                self.assertFalse(ok)
                self.assertIn("PC-DOCTOR-LAN:", out)
                self.assertNotIn(address, out)
        for fp in ("", "a" * 63, "Z" * 64):
            with self.subTest(fp=fp):
                self.assertFalse(self.probe(identity=fp)[0])

    def test_cli_doctor_is_opt_in_and_cannot_start_listener(self):
        with mock.patch.object(readiness, "doctor", return_value=True) as doctor:
            with mock.patch.object(companion, "run_beacon",
                                   side_effect=AssertionError("advertised")):
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(companion.main(["--doctor"]), 0)
            doctor.assert_called_once_with()
        with mock.patch.object(readiness, "doctor", return_value=False):
            self.assertEqual(companion.main(["--doctor"]), 1)
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(companion.main(["--doctor", "--qr"]), 2)
            self.assertEqual(companion.main(["--doctor", "--ip",
                                              "192.168.1.20"]), 2)
            self.assertEqual(companion.main(["--doctor", "--identity-pair"]), 2)

    def test_launchers_are_manual_and_use_exact_qr_v3_flags(self):
        root = ROOT / "examples/windows_companion"
        v3 = (root / "Start-ChappyPairingV3.cmd").read_text(encoding="utf-8")
        known = (root / "Start-ChappyKnownPhoneV3.cmd").read_text(encoding="utf-8")
        setup = (root / "Start-ChappyIdentitySetup.cmd").read_text(encoding="utf-8")
        legacy = (root / "Start-ChappyPairing.cmd").read_text(encoding="utf-8")
        self.assertIn("--start --pair --qr --identity-pair --minutes 10", v3)
        self.assertIn(
            "--start --pair --qr --identity-pair --compare-known-phone --minutes 10",
            known,
        )
        self.assertIn("if errorlevel 1", v3)
        self.assertIn("if errorlevel 1", known)
        self.assertIn("--doctor", v3)
        self.assertIn("--doctor", known)
        self.assertIn('if not "%choice%"=="CREATE"', setup)
        self.assertIn('"ChappyCompanion.exe" --identity-create', setup)
        self.assertIn('--start --pair --qr --minutes 10', legacy)
        self.assertNotIn("--identity-pair", legacy)
        # Neither v3 launcher should create, rotate or revoke any key.
        for launcher in (v3, known):
            self.assertNotIn('"ChappyCompanion.exe" --identity-create', launcher)
            self.assertNotIn('"ChappyCompanion.exe" --identity-revoke', launcher)
        # Never add autostart/service installation or remote-control commands.
        for launcher in (v3, known, setup):
            self.assertNotIn("schtasks", launcher.lower())
            self.assertNotIn("sc create", launcher.lower())
            self.assertNotIn("powershell -enc", launcher.lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)

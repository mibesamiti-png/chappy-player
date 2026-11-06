"""Strict QR invite, expiry, one-use ticket and no-autostart regression tests."""
from __future__ import annotations

import pathlib
import sys
import threading
import time
import unittest
import urllib.error
import urllib.request
import json
from http.server import ThreadingHTTPServer
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "examples" / "windows_companion"))

import companion  # noqa: E402
import pairing_invite  # noqa: E402
import pairing_server as pairing  # noqa: E402

PIN = "a" * 64
TICKET = "b" * 32
NONCE = "0123456789abcdef0123456789abcdef"


class WindowsQrTests(unittest.TestCase):
    def test_exact_invite_can_be_decoded_across_platforms(self):
        now = 1794050000
        data = pairing_invite.create_invitation(
            "192.168.1.77", 45678, PIN, now + 600, TICKET, now=now
        )
        self.assertEqual(
            data,
            "chappy-pair://invite?v=1&ip=192.168.1.77&port=45678"
            "&fp=" + PIN + "&exp=1794050600&ticket=" + TICKET,
        )
        self.assertEqual(
            pairing_invite.parse_invitation(data, now=now),
            {"ip": "192.168.1.77", "port": 45678, "fingerprint": PIN,
             "expires_at": now + 600, "ticket": TICKET},
        )
        self.assertLessEqual(len(data), pairing_invite.MAX_QR_BYTES)

    def test_reject_expired_public_future_or_tampered_qr(self):
        now = 1794050000
        valid = pairing_invite.create_invitation(
            "192.168.1.77", 45678, PIN, now + 600, TICKET, now=now
        )
        altered = [
            valid.replace("192.168.1.77", "8.8.8.8"),
            valid + "&admin=1",
            valid + "&ticket=" + TICKET,
            valid.replace("v=1", "v=2"),
            valid.replace("exp=1794050600", "exp=1794049999"),
            valid.replace("exp=1794050600", "exp=1794053000"),
            valid.replace("&fp=" + PIN, "&fp=bad"),
            valid.replace("ticket=" + TICKET, "ticket=" + "Z" * 32),
            valid.replace("chappy-pair", "https"),
        ]
        for attempt in altered:
            with self.subTest(attempt=attempt), self.assertRaises(ValueError):
                pairing_invite.parse_invitation(attempt, now=now)
        with self.assertRaises(ValueError):
            pairing_invite.parse_invitation(valid, now=now + 600)

    def test_cli_cannot_start_qr_without_explicit_pairing(self):
        with mock.patch.object(companion, "run_beacon") as beacon:
            self.assertEqual(companion.main(["--qr"]), 2)
            self.assertEqual(companion.main(["--start", "--qr"]), 2)
            beacon.assert_not_called()
        with (
            mock.patch.object(companion, "discover_local_ipv4",
                              return_value="192.168.1.77"),
            mock.patch("pairing_server.run_pairing") as pairing_fn,
        ):
            self.assertEqual(
                companion.main(["--start", "--pair", "--qr", "--minutes", "3"]), 0
            )
            pairing_fn.assert_called_once_with("192.168.1.77", 3, qr=True)

    @staticmethod
    def _post(port, ticket=TICKET):
        body = json.dumps({
            "protocol": "pair-preview-v1",
            "nonce": NONCE,
            "ticket": ticket,
        }).encode("ascii")
        req = urllib.request.Request(
            "http://127.0.0.1:" + str(port) + "/v1/pair-preview",
            data=body, headers={"Content-Type": "application/json"}
        )
        return urllib.request.urlopen(req, timeout=2)

    def test_invalid_and_expired_ticket_cannot_consume_one_use_claim(self):
        session = pairing.PairingSession()
        session.invite_ticket = TICKET
        session.expires_at = int(time.time()) + 300
        server = ThreadingHTTPServer(
            ("127.0.0.1", 0), pairing.make_handler(session)
        )
        t = threading.Thread(target=server.serve_forever, daemon=True)
        t.start()
        try:
            with mock.patch.object(pairing, "_ask_pc_user", return_value=True):
                for bad in ["0" * 32, "", "Z" * 32]:
                    with self.assertRaises(urllib.error.HTTPError) as err:
                        self._post(server.server_port, bad)
                    self.assertEqual(err.exception.code, 403)
                    self.assertFalse(session.claimed)
                with self._post(server.server_port) as r:
                    self.assertEqual(r.status, 200)
                with self.assertRaises(urllib.error.HTTPError) as replay:
                    self._post(server.server_port)
                self.assertEqual(replay.exception.code, 409)
                self.assertTrue(session.finished.wait(2))
        finally:
            server.shutdown()
            server.server_close()
            t.join(timeout=2)
        expired = pairing.PairingSession()
        expired.invite_ticket = TICKET
        expired.expires_at = int(time.time()) - 1
        server = ThreadingHTTPServer(
            ("127.0.0.1", 0), pairing.make_handler(expired)
        )
        t = threading.Thread(target=server.serve_forever, daemon=True)
        t.start()
        try:
            with self.assertRaises(urllib.error.HTTPError) as e:
                self._post(server.server_port)
            self.assertEqual(e.exception.code, 403)
            self.assertFalse(expired.claimed)
        finally:
            server.shutdown()
            server.server_close()
            t.join(timeout=2)

    def test_activated_qr_generator_when_installed(self):
        try:
            import qrcode
        except ImportError:
            self.skipTest("qrcode package only installed in Windows build")
        value = pairing_invite.create_invitation(
            "192.168.1.77", 45678, PIN, int(time.time()) + 60, TICKET
        )
        image = qrcode.make(value)
        self.assertGreater(image.width, 10)
        self.assertGreater(image.height, 10)

    def test_sensitive_capability_and_canonical_contract(self):
        server = (ROOT / "examples/windows_companion/pairing_server.py").read_text(
            encoding="utf-8"
        )
        dart = (ROOT / "lib/core/companion_qr_invite.dart").read_text(
            encoding="utf-8"
        )
        host = (ROOT / "lib/core/local_app_server.dart").read_text(
            encoding="utf-8"
        )
        self.assertIn("secrets.compare_digest", server)
        self.assertIn("session.expires_at", server)
        self.assertIn("session.claim()", server)
        self.assertIn("chappy-pair://invite", dart)
        self.assertNotIn("pair-preview-v1", host)
        self.assertNotIn("chappy-pair://invite", host)


if __name__ == "__main__":
    unittest.main(verbosity=2)

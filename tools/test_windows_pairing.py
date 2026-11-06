"""Offline regression tests for one-session manual PC confirmation.

The isolated HTTP handler tests use loopback without TLS only inside tests.
Production always uses a self-signed TLS certificate pinned on Android.
"""
from __future__ import annotations

import json
import pathlib
import sys
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "examples" / "windows_companion"))

import pairing_server as pairing  # noqa: E402


NONCE = "0123456789abcdef0123456789abcdef"


class PairingTests(unittest.TestCase):
    def test_confirmation_vector_and_reject_invalid_nonce(self):
        self.assertEqual(pairing.confirmation_code(NONCE), "223E0A")
        for bad in ("", "X" * 32, "abcdef", "a" * 33, "A" * 32):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                pairing.confirmation_code(bad)

    def test_claim_exactly_once(self):
        session = pairing.PairingSession()
        self.assertTrue(session.claim())
        self.assertFalse(session.claim())
        self.assertFalse(session.finished.is_set())

    def test_certificate_generated_with_ip_san_and_fresh_pin(self):
        try:
            from cryptography import x509
            from cryptography.hazmat.primitives import hashes
        except ImportError:
            self.skipTest("TLS certificate dependency installed in Windows CI")
        pem1, key1, fingerprint1 = pairing.create_ephemeral_certificate(
            "192.168.1.77"
        )
        pem2, key2, fingerprint2 = pairing.create_ephemeral_certificate(
            "192.168.1.77"
        )
        cert = x509.load_pem_x509_certificate(pem1)
        san = cert.extensions.get_extension_for_class(
            x509.SubjectAlternativeName
        ).value
        self.assertEqual(len(cert.fingerprint(hashes.SHA256()).hex()), 64)
        self.assertIn("192.168.1.77", [str(ip) for ip in san.get_values_for_type(x509.IPAddress)])
        self.assertEqual(cert.fingerprint(hashes.SHA256()).hex(), fingerprint1)
        self.assertNotEqual(fingerprint1, fingerprint2)
        self.assertNotEqual(key1, key2)
        with self.assertRaises(ValueError):
            pairing.create_ephemeral_certificate("8.8.8.8")

    def _request(self, port, payload=None):
        data = json.dumps(payload if payload is not None else {
            "protocol": "pair-preview-v1",
            "nonce": NONCE,
        }).encode()
        request = urllib.request.Request(
            "http://127.0.0.1:" + str(port) + "/v1/pair-preview",
            data=data,
            headers={"Content-Type": "application/json"},
        )
        return urllib.request.urlopen(request, timeout=2)

    def test_one_time_pc_approval_and_replay_refusal(self):
        session = pairing.PairingSession()
        server = ThreadingHTTPServer(
            ("127.0.0.1", 0), pairing.make_handler(session)
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with mock.patch.object(pairing, "_ask_pc_user", return_value=True) as ask:
                with self._request(server.server_port) as response:
                    self.assertEqual(response.status, 200)
                    self.assertEqual(response.headers["Cache-Control"], "no-store")
                    answer = json.load(response)
                    self.assertEqual(answer, {
                        "status": "approved",
                        "protocol": "pair-preview-v1", "nonce": NONCE,
                    })
                ask.assert_called_once_with(NONCE)
                with self.assertRaises(urllib.error.HTTPError) as error:
                    self._request(server.server_port)
                self.assertEqual(error.exception.code, 409)
                self.assertTrue(session.finished.wait(2))
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_invalid_and_denied_requests_do_not_succeed(self):
        session = pairing.PairingSession()
        server = ThreadingHTTPServer(
            ("127.0.0.1", 0), pairing.make_handler(session)
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with mock.patch.object(pairing, "_ask_pc_user", return_value=False):
                with self.assertRaises(urllib.error.HTTPError) as invalid:
                    self._request(server.server_port, {
                        "protocol": "pair-preview-v1", "nonce": "nope"
                    })
                self.assertEqual(invalid.exception.code, 400)
                self.assertFalse(session.claimed)
                with self.assertRaises(urllib.error.HTTPError) as denied:
                    self._request(server.server_port)
                self.assertEqual(denied.exception.code, 403)
                self.assertTrue(session.finished.wait(2))
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_privacy_contract(self):
        server = (ROOT / "examples/windows_companion/pairing_server.py").read_text()
        client = (ROOT / "lib/core/companion_pairing_client.dart").read_text()
        host = (ROOT / "tools/android/MainActivity.kt").read_text()
        bridge = (ROOT / "lib/core/local_app_server.dart").read_text()
        for item in (
            "ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)",
            "ssl.TLSVersion.TLSv1_2",
            "create_ephemeral_certificate",
            "MAX_REQUEST = 256",
            "MAX_APPROVAL_SECONDS = 25",
            "session.claim()",
            "connection.settimeout(3.0)",
            "zeroconf.unregister_service(info)",
            "pem_key.unlink(missing_ok=True)",
        ):
            self.assertIn(item, server, item)
        for item in (
            "SecureSocket.connect",
            "onBadCertificate",
            "socket.peerCertificate",
            "sha256.convert(cert.der)",
            "2048",
            "isPrivateIpv4",
            "void cancel()",
        ):
            self.assertIn(item, client, item)
        self.assertIn('"pairingAllowed"', host)
        self.assertNotIn("pair-preview-v1", bridge)
        self.assertNotIn("executeCommand", server)
        self.assertNotIn("subprocess.", server)


if __name__ == "__main__":
    unittest.main(verbosity=2)

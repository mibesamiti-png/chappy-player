"""R4C: signed, independently consented status after REAL QR-v3 proof.

The tiny in-process and 127.0.0.1 HTTP fixtures are test only, not a
substitute for physical pinned-TLS Android/Windows two-device QA.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import sys
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from unittest import mock

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "examples/windows_companion"))
import identity_pairing_v3 as v3
import identity_proof as proof
import pairing_server as server
import companion
from status_once import StatusOnceAttempt, scoped_nonce, PROTOCOL
from pc_status_metrics import read_pc_status

INV, TLS, PHONE_NONCE = "a" * 32, "b" * 64, "c" * 64

def fingerprint(key):
    raw = key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    return hashlib.sha256(raw).hexdigest()


class PcStatusOnceTests(unittest.TestCase):
    def setUp(self):
        self.pc = ec.generate_private_key(ec.SECP256R1())
        self.phone = ec.generate_private_key(ec.SECP256R1())
        self.pc_fp = fingerprint(self.pc)
        self.phone_fp = fingerprint(self.phone)
        self.expires = int(time.time()) + 240
        self.pc_sign = lambda **k: proof._sign_with_key(self.pc, role="pc", **k)
        self.metrics = {"available": True, "logical_cpus": 8,
                        "memory_total_bytes": 16 * 1024**3,
                        "memory_available_bytes": 4 * 1024**3,
                        "uptime_seconds": 5400}
        self.identity = v3.IdentityPairingAttempt(
            invitation=INV, qr_expires=self.expires, tls_fingerprint=TLS,
            pc_fingerprint=self.pc_fp, signer=self.pc_sign)
        self.status = StatusOnceAttempt(
            identity=self.identity, invitation=INV, qr_expires=self.expires,
            tls_fingerprint=TLS, pc_fingerprint=self.pc_fp, signer=self.pc_sign,
            status_reader=lambda: dict(self.metrics))

    def authenticate(self):
        first = self.identity.begin(
            invitation=INV, phone_fingerprint=self.phone_fp,
            phone_nonce=PHONE_NONCE, approve_on_pc=lambda _: True)
        signature = proof._sign_with_key(
            self.phone, role="android", invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=self.pc_fp, nonce=first["pc_nonce"],
            expires_at=first["expires"])
        self.assertEqual("approved", self.identity.finish(
            invitation=INV, phone_fingerprint=self.phone_fp,
            phone_proof=signature)["status"])

    def begin(self, yes=lambda: True):
        return self.status.begin(
            invitation=INV, phone_fp=self.phone_fp, phone_nonce=PHONE_NONCE,
            approve_pc_status=yes)

    def signature(self, challenge, *, key=None, scoped=True):
        return proof._sign_with_key(
            key or self.phone, role="android", invitation=INV,
            tls_fingerprint=TLS, peer_fingerprint=self.pc_fp,
            nonce=(scoped_nonce(challenge["pc_nonce"]) if scoped
                   else challenge["pc_nonce"]),
            expires_at=challenge["expires"])

    def test_cannot_read_after_identity_without_separate_pc_consent(self):
        with self.assertRaises(ValueError):
            self.begin()
        self.assertFalse(self.status.finished.is_set())
        self.authenticate()
        with self.assertRaises(PermissionError):
            self.begin(lambda: False)
        self.assertTrue(self.status.finished.is_set())
        with self.assertRaises(PermissionError):
            self.begin()

    def test_scoped_signatures_approve_one_read_only_request(self):
        self.authenticate()
        challenge = self.begin()
        self.assertEqual(challenge["protocol"], PROTOCOL)
        self.assertTrue(proof.verify_identity_proof(
            challenge["pc_proof"], expected_signer_fingerprint=self.pc_fp,
            role="pc", invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=self.phone_fp,
            nonce=scoped_nonce(PHONE_NONCE), expires_at=challenge["expires"]))
        self.assertFalse(proof.verify_identity_proof(
            challenge["pc_proof"], expected_signer_fingerprint=self.pc_fp,
            role="pc", invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=self.phone_fp, nonce=PHONE_NONCE,
            expires_at=challenge["expires"]))
        answer = self.status.finish(
            invitation=INV, phone_fp=self.phone_fp,
            phone_proof=self.signature(challenge))
        self.assertEqual(answer["metrics"], self.metrics)
        self.assertTrue(self.status.finished.is_set())
        with self.assertRaises(PermissionError):
            self.status.finish(
                invitation=INV, phone_fp=self.phone_fp,
                phone_proof=self.signature(challenge))

    def test_wrong_device_key_or_old_identity_signature_rejected(self):
        self.authenticate()
        changed = fingerprint(ec.generate_private_key(ec.SECP256R1()))
        with self.assertRaises(PermissionError):
            self.status.begin(invitation=INV, phone_fp=changed,
                              phone_nonce=PHONE_NONCE,
                              approve_pc_status=lambda: self.fail("No prompt"))
        challenge = self.begin()
        with self.assertRaises(ValueError):
            self.status.finish(
                invitation=INV, phone_fp=self.phone_fp,
                phone_proof=self.signature(challenge, scoped=False))
        self.assertTrue(self.status.finished.is_set())

    def test_bad_provider_never_leaks_unstructured_data(self):
        self.authenticate()
        self.status._status_reader = lambda: dict(self.metrics, hostname="private")
        challenge = self.begin()
        with self.assertRaises(ValueError):
            self.status.finish(
                invitation=INV, phone_fp=self.phone_fp,
                phone_proof=self.signature(challenge))
        self.assertTrue(self.status.finished.is_set())

    def test_status_qr_is_opt_in_v3_only_no_background_cli(self):
        qr = server.invite_payload(
            "192.168.1.5", 40000, TLS, INV, self.expires,
            identity_fingerprint=self.pc_fp, status_once=True)
        self.assertTrue(qr.endswith("&status=1"))
        with self.assertRaises(ValueError):
            server.invite_payload("192.168.1.5", 40000, TLS, INV,
                                  self.expires, status_once=True)
        self.assertEqual(companion.main(["--status-once"]), 2)
        self.assertEqual(companion.main(["--start", "--status-once"]), 2)
        self.assertEqual(companion.main([]), 0)

    def test_status_http_routes_are_strict_after_verified_qr(self):
        self.authenticate()
        legacy = server.PairingSession(invitation=INV, expires_at=self.expires)
        httpd = ThreadingHTTPServer(
            ("127.0.0.1", 0), server.make_handler(legacy, self.identity, self.status))
        worker = threading.Thread(target=httpd.serve_forever, daemon=True)
        worker.start()
        def send(path, payload):
            request = urllib.request.Request(
                "http://127.0.0.1:" + str(httpd.server_port) + path,
                data=json.dumps(payload).encode(),
                headers={"Content-Type": "application/json"})
            return urllib.request.urlopen(request, timeout=5)
        req = {"protocol": PROTOCOL, "invitation": INV,
               "phone_fp": self.phone_fp, "phone_nonce": PHONE_NONCE}
        try:
            with self.assertRaises(urllib.error.HTTPError) as bad:
                send("/v3/status-begin", dict(req, command="exec"))
            self.assertEqual(bad.exception.code, 403)
            with mock.patch.object(server, "_ask_pc_status_user", return_value=True):
                with send("/v3/status-begin", req) as reply:
                    challenge = json.load(reply)
            with send("/v3/status-finish", {
                "protocol": PROTOCOL, "invitation": INV,
                "phone_fp": self.phone_fp,
                "phone_proof": self.signature(challenge),
            }) as reply:
                result = json.load(reply)
            self.assertEqual(result["metrics"], self.metrics)
            with self.assertRaises(urllib.error.HTTPError) as replay:
                send("/v3/status-finish", {
                    "protocol": PROTOCOL, "invitation": INV,
                    "phone_fp": self.phone_fp,
                    "phone_proof": self.signature(challenge)})
            self.assertEqual(replay.exception.code, 403)
        finally:
            httpd.shutdown()
            httpd.server_close()
            worker.join(timeout=3)

    def test_real_windows_provider_contains_no_private_fields(self):
        import platform
        if platform.system() != "Windows":
            value = read_pc_status()
            self.assertEqual(value["available"], False)
            self.assertTrue(all(v is None for k,v in value.items()
                                if k != "available"))
        else:
            value = read_pc_status()
            self.assertIsInstance(value["available"], bool)
        self.assertEqual(set(value), {"available", "logical_cpus",
            "memory_total_bytes", "memory_available_bytes", "uptime_seconds"})
        for key in ("hostname", "username", "files", "processes", "ip", "network"):
            self.assertNotIn(key, value)


if __name__ == "__main__":
    unittest.main(verbosity=2)

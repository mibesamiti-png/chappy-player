"""NETLAB-04B isolated signed one-shot owner-PC traffic regressions.

Loopback HTTP is TEST-ONLY. Production always requires QR-pinned TLS.
No live packets, actual LAN connections or physical QA are exercised.
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
from traffic_once import TrafficOnceAttempt, scoped_nonce, PROTOCOL
from status_once import scoped_nonce as status_scoped

INV = "a" * 32
TLS = "b" * 64
NONCE = "c" * 64

def fingerprint(key):
    data = key.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo)
    return hashlib.sha256(data).hexdigest()

def report(seconds=10):
    points = [{"rx_bytes": 100 + i, "tx_bytes": 20 + i}
              for i in range(seconds)]
    return {"format": "chappy.remote-traffic.v1",
            "source": "windows_pc", "coverage": "all_interfaces",
            "interval_ms": 1000, "samples": points,
            "totals": {"rx_bytes": sum(p["rx_bytes"] for p in points),
                       "tx_bytes": sum(p["tx_bytes"] for p in points)}}

class TrafficOnceTests(unittest.TestCase):
    def setUp(self):
        self.pc = ec.generate_private_key(ec.SECP256R1())
        self.phone = ec.generate_private_key(ec.SECP256R1())
        self.pc_fp = fingerprint(self.pc)
        self.phone_fp = fingerprint(self.phone)
        self.exp = int(time.time()) + 240
        self.pc_sign = lambda **kw: proof._sign_with_key(self.pc, role="pc", **kw)
        self.identity = v3.IdentityPairingAttempt(
            invitation=INV, qr_expires=self.exp, tls_fingerprint=TLS,
            pc_fingerprint=self.pc_fp, signer=self.pc_sign)
        self.reader_calls = []
        def capture_mock(seconds):
            self.reader_calls.append(seconds)
            return report(seconds)
        self.traffic = TrafficOnceAttempt(
            identity=self.identity, invitation=INV, qr_expires=self.exp,
            tls_fingerprint=TLS, pc_fingerprint=self.pc_fp,
            signer=self.pc_sign, traffic_reader=capture_mock, seconds=10)

    def authenticate(self):
        first = self.identity.begin(
            invitation=INV, phone_fingerprint=self.phone_fp,
            phone_nonce=NONCE, approve_on_pc=lambda _: True)
        android_proof = proof._sign_with_key(
            self.phone, role="android", invitation=INV,
            tls_fingerprint=TLS, peer_fingerprint=self.pc_fp,
            nonce=first["pc_nonce"], expires_at=first["expires"])
        self.assertEqual(self.identity.finish(
            invitation=INV, phone_fingerprint=self.phone_fp,
            phone_proof=android_proof)["status"], "approved")

    def begin(self, allow=True):
        return self.traffic.begin(
            invitation=INV, phone_fp=self.phone_fp, phone_nonce=NONCE,
            approve_pc_traffic=lambda: allow)

    def sign(self, challenge, scoped=True, key=None):
        return proof._sign_with_key(
            key or self.phone, role="android", invitation=INV,
            tls_fingerprint=TLS, peer_fingerprint=self.pc_fp,
            nonce=(scoped_nonce(challenge["pc_nonce"], challenge["seconds"])
                   if scoped else challenge["pc_nonce"]),
            expires_at=challenge["expires"])

    def test_shared_python_dart_domain_vectors_and_cross_scope(self):
        data = json.loads((ROOT / "docs/netlab-04b-traffic-vectors.json").read_text())
        self.assertEqual(data["format"], "chappy.netlab-04b-traffic-v1")
        for row in data["cases"]:
            self.assertEqual(scoped_nonce(row["nonce"], row["seconds"]), row["sha256"])
        self.assertNotEqual(scoped_nonce(NONCE, 10), status_scoped(NONCE))
        self.assertNotEqual(scoped_nonce(NONCE, 5), scoped_nonce(NONCE, 10))
        for duration in (0, 4, 31, True):
            with self.assertRaises(ValueError):
                scoped_nonce(NONCE, duration)

    def test_no_capture_without_identity_and_separate_windows_permission(self):
        with self.assertRaises(ValueError):
            self.begin()
        self.authenticate()
        with self.assertRaises(PermissionError):
            self.begin(False)
        self.assertTrue(self.traffic.finished.is_set())
        self.assertEqual(self.reader_calls, [])

    def test_single_signed_read_and_replay_denial(self):
        self.authenticate()
        challenge = self.begin()
        self.assertEqual(challenge["protocol"], PROTOCOL)
        self.assertEqual(challenge["seconds"], 10)
        self.assertTrue(proof.verify_identity_proof(
            challenge["pc_proof"], expected_signer_fingerprint=self.pc_fp,
            role="pc", invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=self.phone_fp, nonce=scoped_nonce(NONCE, 10),
            expires_at=challenge["expires"]))
        answer = self.traffic.finish(
            invitation=INV, phone_fp=self.phone_fp,
            phone_proof=self.sign(challenge))
        self.assertEqual(answer["status"], "ok")
        self.assertEqual(answer["report"], report(10))
        self.assertEqual(self.reader_calls, [10])
        with self.assertRaises(PermissionError):
            self.traffic.finish(invitation=INV, phone_fp=self.phone_fp,
                                phone_proof=self.sign(challenge))
        self.assertEqual(self.reader_calls, [10])

    def test_identity_or_other_scope_proof_cannot_read(self):
        self.authenticate()
        challenge = self.begin()
        with self.assertRaises(ValueError):
            self.traffic.finish(invitation=INV, phone_fp=self.phone_fp,
                                phone_proof=self.sign(challenge, scoped=False))
        self.assertEqual(self.reader_calls, [])
        self.assertTrue(self.traffic.finished.is_set())

    def test_bad_report_with_identifiers_or_totals_is_never_returned(self):
        self.authenticate()
        self.traffic._traffic_reader = lambda _: dict(report(), hostname="private")
        challenge = self.begin()
        with self.assertRaises(ValueError):
            self.traffic.finish(invitation=INV, phone_fp=self.phone_fp,
                                phone_proof=self.sign(challenge))
        self.assertTrue(self.traffic.finished.is_set())

    def test_pc_stop_during_capture_does_not_return_traffic(self):
        self.authenticate()
        challenge = self.begin()
        def interrupted(seconds):
            self.traffic.cancel()
            return report(seconds)
        self.traffic._traffic_reader = interrupted
        with self.assertRaises(PermissionError):
            self.traffic.finish(
                invitation=INV, phone_fp=self.phone_fp,
                phone_proof=self.sign(challenge))
        self.assertTrue(self.traffic.finished.is_set())

    def test_qr_and_cli_are_opt_in_not_reusable_other_permissions(self):
        qr = server.invite_payload("192.168.1.5", 40000, TLS, INV,
            self.exp, identity_fingerprint=self.pc_fp, traffic_once=True)
        self.assertTrue(qr.endswith("&traffic=1"))
        with self.assertRaises(ValueError):
            server.invite_payload("192.168.1.5", 40000, TLS, INV, self.exp,
                                  traffic_once=True)
        with self.assertRaises(ValueError):
            server.invite_payload("192.168.1.5", 40000, TLS, INV, self.exp,
                identity_fingerprint=self.pc_fp, traffic_once=True,
                media_once=True)
        self.assertEqual(companion.main(["--traffic-read-once"]), 2)
        self.assertEqual(companion.main(["--start", "--traffic-read-once"]), 2)
        self.assertEqual(companion.main(["--traffic-read-seconds", "15"]), 2)
        self.assertEqual(companion.main(["--traffic-read-once", "--traffic-read-seconds", "31"]), 2)

    def test_test_only_localhost_http_real_signature_and_replay(self):
        self.authenticate()
        pair = server.PairingSession(invitation=INV, expires_at=self.exp)
        handler = server.make_handler(pair, self.identity, None, None, None,
                                      None, self.traffic)
        http = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=http.serve_forever, daemon=True)
        thread.start()
        try:
            def post(route, body):
                request = urllib.request.Request(
                    f"http://127.0.0.1:{http.server_port}/v3/{route}",
                    json.dumps(body).encode("utf-8"),
                    {"Content-Type": "application/json"}, method="POST")
                with urllib.request.urlopen(request, timeout=5) as response:
                    return json.load(response)
            with mock.patch.object(server, "_ask_pc_traffic_user",
                                   side_effect=lambda seconds: seconds == 10):
                challenge = post("traffic-begin", {
                    "protocol": PROTOCOL, "invitation": INV,
                    "phone_fp": self.phone_fp, "phone_nonce": NONCE})
                answer = post("traffic-finish", {
                    "protocol": PROTOCOL, "invitation": INV,
                    "phone_fp": self.phone_fp,
                    "phone_proof": self.sign(challenge)})
                self.assertEqual(answer["report"], report(10))
                with self.assertRaises(urllib.error.HTTPError):
                    post("traffic-finish", {
                        "protocol": PROTOCOL, "invitation": INV,
                        "phone_fp": self.phone_fp,
                        "phone_proof": self.sign(challenge)})
                self.assertEqual(self.reader_calls, [10])
        finally:
            http.shutdown()
            http.server_close()
            thread.join(timeout=3)

if __name__ == "__main__":
    unittest.main()

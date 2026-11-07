"""NETLAB-03B-4 QR-v3 offline state machine and HTTP handler contracts.

Uses isolated localhost HTTP only for unit tests. Real connection is pinned TLS.
No PC trust storage, traffic reading, file transfer or remote-control access.
"""
from __future__ import annotations

import hashlib
import http.client
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
sys.path.insert(0, str(ROOT / "examples" / "windows_companion"))

import identity_pairing_v3 as v3  # noqa: E402
import identity_proof as proof  # noqa: E402
import pairing_server as server  # noqa: E402
import companion  # noqa: E402

INV = "a" * 32
TLS = "b" * 64
PHONE_NONCE = "c" * 64


def fingerprint(key):
    spki = key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return hashlib.sha256(spki).hexdigest()


class IdentityV3Tests(unittest.TestCase):
    def setUp(self):
        self.pc = ec.generate_private_key(ec.SECP256R1())
        self.phone = ec.generate_private_key(ec.SECP256R1())
        self.pc_fp = fingerprint(self.pc)
        self.phone_fp = fingerprint(self.phone)
        self.expiry = int(time.time()) + 240
        self.calls = []

        def pc_signer(**kwargs):
            self.calls.append(kwargs)
            return proof._sign_with_key(self.pc, role="pc", **kwargs)

        self.signer = pc_signer

    def session(self):
        return v3.IdentityPairingAttempt(
            invitation=INV, qr_expires=self.expiry, tls_fingerprint=TLS,
            pc_fingerprint=self.pc_fp, signer=self.signer,
        )

    def phone_proof(self, begin):
        return proof._sign_with_key(
            self.phone, role="android", invitation=INV,
            tls_fingerprint=TLS, peer_fingerprint=self.pc_fp,
            nonce=begin["pc_nonce"], expires_at=begin["expires"],
        )

    def test_v3_qr_strict_pc_identity_and_legacy_compatibility(self):
        legacy = server.invite_payload(
            "192.168.1.7", 49152, TLS, INV, self.expiry,
        )
        modern = server.invite_payload(
            "192.168.1.7", 49152, TLS, INV, self.expiry,
            identity_fingerprint=self.pc_fp,
        )
        self.assertIn("chappy-pair://v2?", legacy)
        self.assertNotIn("&pc=", legacy)
        self.assertIn("chappy-pair://v3?", modern)
        self.assertTrue(modern.endswith("&pc=" + self.pc_fp))
        self.assertLess(len(modern), 384)
        with self.assertRaises(ValueError):
            server.invite_payload(
                "192.168.1.7", 49152, TLS, INV, self.expiry,
                identity_fingerprint="X" * 64,
            )

    def test_full_two_device_proof_and_replay_refusal(self):
        s = self.session()
        approvals = []
        def approve(nonce):
            approvals.append(nonce)
            return True
        begin = s.begin(
            invitation=INV, phone_fingerprint=self.phone_fp,
            phone_nonce=PHONE_NONCE, approve_on_pc=approve,
        )
        self.assertEqual(approvals, [PHONE_NONCE])
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(begin["phone_nonce"], PHONE_NONCE)
        self.assertRegex(begin["pc_nonce"], r"^[a-f0-9]{64}$")
        self.assertTrue(proof.verify_identity_proof(
            begin["pc_proof"], expected_signer_fingerprint=self.pc_fp,
            role="pc", invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=self.phone_fp, nonce=PHONE_NONCE,
            expires_at=begin["expires"],
        ))
        with self.assertRaises(ValueError):
            s.begin(
                invitation=INV, phone_fingerprint=self.phone_fp,
                phone_nonce=PHONE_NONCE, approve_on_pc=approve,
            )
        answer = s.finish(
            invitation=INV, phone_fingerprint=self.phone_fp,
            phone_proof=self.phone_proof(begin),
        )
        self.assertEqual(answer["status"], "approved")
        self.assertEqual(answer["pc_nonce"], begin["pc_nonce"])
        self.assertTrue(s.finished.is_set())
        with self.assertRaises(ValueError):
            s.finish(
                invitation=INV, phone_fingerprint=self.phone_fp,
                phone_proof=self.phone_proof(begin),
            )

    def test_manual_known_phone_comparison_rejects_changed_key_before_consent(self):
        expected = self.phone_fp
        other = fingerprint(ec.generate_private_key(ec.SECP256R1()))
        session = v3.IdentityPairingAttempt(
            invitation=INV, qr_expires=self.expiry, tls_fingerprint=TLS,
            pc_fingerprint=self.pc_fp, signer=self.signer,
            expected_phone_fingerprint=expected,
        )
        approve = mock.Mock(return_value=True)
        with self.assertRaisesRegex(ValueError, "differs"):
            session.begin(
                invitation=INV, phone_fingerprint=other,
                phone_nonce=PHONE_NONCE, approve_on_pc=approve,
            )
        approve.assert_not_called()
        self.assertEqual(self.calls, [])
        self.assertFalse(session.finished.is_set())
        self.assertIsNone(session.verified_phone_fingerprint)

        # An unrelated spoofed claim must not consume the one-use QR.
        begin = session.begin(
            invitation=INV, phone_fingerprint=expected,
            phone_nonce=PHONE_NONCE, approve_on_pc=approve,
        )
        approve.assert_called_once_with(PHONE_NONCE)
        self.assertEqual(len(self.calls), 1)
        self.assertIsNone(session.verified_phone_fingerprint)
        result = session.finish(
            invitation=INV, phone_fingerprint=expected,
            phone_proof=self.phone_proof(begin),
        )
        self.assertEqual(result["status"], "approved")
        self.assertEqual(session.verified_phone_fingerprint, expected)

    def test_claimed_known_phone_still_requires_actual_private_key_signature(self):
        other_key = ec.generate_private_key(ec.SECP256R1())
        session = v3.IdentityPairingAttempt(
            invitation=INV, qr_expires=self.expiry, tls_fingerprint=TLS,
            pc_fingerprint=self.pc_fp, signer=self.signer,
            expected_phone_fingerprint=self.phone_fp,
        )
        begin = session.begin(
            invitation=INV, phone_fingerprint=self.phone_fp,
            phone_nonce=PHONE_NONCE, approve_on_pc=lambda _: True,
        )
        forged = proof._sign_with_key(
            other_key, role="android", invitation=INV,
            tls_fingerprint=TLS, peer_fingerprint=self.pc_fp,
            nonce=begin["pc_nonce"], expires_at=begin["expires"],
        )
        with self.assertRaises(ValueError):
            session.finish(
                invitation=INV, phone_fingerprint=self.phone_fp,
                phone_proof=forged,
            )
        self.assertIsNone(session.verified_phone_fingerprint)
        self.assertTrue(session.finished.is_set())

    def test_manual_phone_expectation_rejects_bad_fingerprint_at_bootstrap(self):
        for bad in ("", "X" * 64, "a" * 63, "0" * 65, 11):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                v3.IdentityPairingAttempt(
                    invitation=INV, qr_expires=self.expiry,
                    tls_fingerprint=TLS, pc_fingerprint=self.pc_fp,
                    expected_phone_fingerprint=bad,
                )

    def test_http_changed_phone_key_is_rejected_before_yes_or_qr_claim(self):
        other_key = ec.generate_private_key(ec.SECP256R1())
        other_fp = fingerprint(other_key)
        state = v3.IdentityPairingAttempt(
            invitation=INV, qr_expires=self.expiry,
            tls_fingerprint=TLS, pc_fingerprint=self.pc_fp,
            signer=self.signer, expected_phone_fingerprint=self.phone_fp,
        )
        legacy = server.PairingSession(invitation=INV, expires_at=self.expiry)
        httpd = ThreadingHTTPServer(
            ("127.0.0.1", 0), server.make_handler(legacy, state),
        )
        worker = threading.Thread(target=httpd.serve_forever, daemon=True)
        worker.start()

        def begin(fp):
            request = urllib.request.Request(
                "http://127.0.0.1:" + str(httpd.server_port)
                + "/v3/identity-begin",
                data=json.dumps({
                    "protocol": v3.PROTOCOL, "invitation": INV,
                    "phone_fp": fp, "phone_nonce": PHONE_NONCE,
                }).encode("utf-8"),
                headers={"Content-Type": "application/json"},
            )
            return urllib.request.urlopen(request, timeout=4)

        try:
            with mock.patch.object(server, "_ask_pc_user",
                                   return_value=True) as ask:
                with self.assertRaises(urllib.error.HTTPError) as rejected:
                    begin(other_fp)
                self.assertEqual(rejected.exception.code, 403)
                ask.assert_not_called()
                self.assertFalse(state.finished.is_set())
                self.assertFalse(legacy.claimed)
                self.assertEqual(self.calls, [])

                with begin(self.phone_fp) as response:
                    answer = json.load(response)
                self.assertEqual(answer["status"], "challenge")
                ask.assert_called_once_with(PHONE_NONCE)
                self.assertFalse(legacy.claimed)
        finally:
            httpd.shutdown()
            httpd.server_close()
            worker.join(timeout=2)

    def test_invalid_begin_does_not_sign_or_approve(self):
        s = self.session()
        approve = mock.Mock(return_value=True)
        for kwargs in (
            {"invitation": "e" * 32},
            {"phone_fingerprint": "Z" * 64},
            {"phone_nonce": "invalid"},
            {"invitation": INV.upper()},
        ):
            values = dict(
                invitation=INV, phone_fingerprint=self.phone_fp,
                phone_nonce=PHONE_NONCE, approve_on_pc=approve,
            )
            values.update(kwargs)
            with self.assertRaises(ValueError):
                s.begin(**values)
        approve.assert_not_called()
        self.assertEqual(self.calls, [])
        self.assertFalse(s.finished.is_set())

    def test_pc_denial_and_wrong_identity_never_succeed(self):
        s = self.session()
        with self.assertRaises(PermissionError):
            s.begin(
                invitation=INV, phone_fingerprint=self.phone_fp,
                phone_nonce=PHONE_NONCE, approve_on_pc=lambda _: False,
            )
        self.assertEqual(self.calls, [])
        self.assertTrue(s.finished.is_set())
        with self.assertRaises(ValueError):
            s.begin(
                invitation=INV, phone_fingerprint=self.phone_fp,
                phone_nonce=PHONE_NONCE, approve_on_pc=lambda _: True,
            )
        def wrong_signer(**kwargs):
            return proof._sign_with_key(
                ec.generate_private_key(ec.SECP256R1()), role="pc", **kwargs,
            )
        s = v3.IdentityPairingAttempt(
            invitation=INV, qr_expires=self.expiry, tls_fingerprint=TLS,
            pc_fingerprint=self.pc_fp, signer=wrong_signer,
        )
        with self.assertRaises(ValueError):
            s.begin(
                invitation=INV, phone_fingerprint=self.phone_fp,
                phone_nonce=PHONE_NONCE, approve_on_pc=lambda _: True,
            )
        self.assertTrue(s.finished.is_set())

    def test_replay_wrong_key_and_tampering_consume_final_challenge(self):
        for attack in ("wrongkey", "altered", "wronginvite", "wrongpeer"):
            with self.subTest(attack=attack):
                s = self.session()
                begin = s.begin(
                    invitation=INV, phone_fingerprint=self.phone_fp,
                    phone_nonce=PHONE_NONCE, approve_on_pc=lambda _: True,
                )
                signed = self.phone_proof(begin)
                invite = INV
                phone_fp = self.phone_fp
                if attack == "wrongkey":
                    signed = proof._sign_with_key(
                        ec.generate_private_key(ec.SECP256R1()),
                        role="android", invitation=INV, tls_fingerprint=TLS,
                        peer_fingerprint=self.pc_fp, nonce=begin["pc_nonce"],
                        expires_at=begin["expires"],
                    )
                elif attack == "altered":
                    signed["signature"] = "broken!!"
                elif attack == "wronginvite":
                    invite = "f" * 32
                else:
                    phone_fp = self.pc_fp
                with self.assertRaises(ValueError):
                    s.finish(
                        invitation=invite, phone_fingerprint=phone_fp,
                        phone_proof=signed,
                    )
                self.assertTrue(s.finished.is_set())
                with self.assertRaises(ValueError):
                    s.finish(
                        invitation=INV, phone_fingerprint=self.phone_fp,
                        phone_proof=self.phone_proof(begin),
                    )

    def test_expired_invitation_is_rejected(self):
        s = self.session()
        with mock.patch.object(v3.time, "time", return_value=self.expiry):
            with self.assertRaises(ValueError):
                s.begin(
                    invitation=INV, phone_fingerprint=self.phone_fp,
                    phone_nonce=PHONE_NONCE, approve_on_pc=lambda _: True,
                )
        self.assertEqual(self.calls, [])

    def test_comparison_code_is_not_authentication_secret(self):
        self.assertRegex(v3.comparison_code(PHONE_NONCE), r"^[0-9A-F]{6}$")
        self.assertEqual(
            v3.comparison_code(PHONE_NONCE),
            hashlib.sha256(bytes.fromhex(PHONE_NONCE)).hexdigest()[:6].upper(),
        )
        for invalid in ("a" * 32, "Z" * 64, ""):
            with self.assertRaises(ValueError):
                v3.comparison_code(invalid)

    def test_http_v3_begin_finish_and_no_cross_protocol_downgrade(self):
        s = self.session()
        legacy = server.PairingSession(invitation=INV, expires_at=self.expiry)
        http = ThreadingHTTPServer(
            ("127.0.0.1", 0), server.make_handler(legacy, s),
        )
        runner = threading.Thread(target=http.serve_forever, daemon=True)
        runner.start()

        def send(path, data):
            request = urllib.request.Request(
                "http://127.0.0.1:" + str(http.server_port) + path,
                data=json.dumps(data).encode("utf-8"),
                headers={"Content-Type": "application/json"},
            )
            return urllib.request.urlopen(request, timeout=4)

        try:
            with mock.patch.object(server, "_ask_pc_user", return_value=True) as approve:
                begin_request = {
                    "protocol": v3.PROTOCOL, "invitation": INV,
                    "phone_fp": self.phone_fp, "phone_nonce": PHONE_NONCE,
                }
                with send("/v3/identity-begin", begin_request) as r:
                    self.assertEqual(r.status, 200)
                    begin = json.load(r)
                approve.assert_called_once_with(PHONE_NONCE)
                with self.assertRaises(urllib.error.HTTPError):
                    send("/v3/identity-begin", begin_request)
                with send("/v3/identity-finish", {
                    "protocol": v3.PROTOCOL, "invitation": INV,
                    "phone_fp": self.phone_fp,
                    "phone_proof": self.phone_proof(begin),
                }) as r:
                    self.assertEqual(json.load(r)["status"], "approved")
                self.assertTrue(s.finished.is_set())
                self.assertFalse(legacy.claimed)
        finally:
            http.shutdown()
            http.server_close()
            runner.join(timeout=2)

    def test_v3_json_duplicates_and_http_framing_are_rejected_without_claiming(self):
        for raw in (
            b'{"protocol":"pair-identity-v3","protocol":"pair-identity-v3"}',
            b'{"phone_proof":{"spki":"a","spki":"b"}}',
            b'[]',
        ):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                server._strict_identity_json(raw)
        self.assertEqual(
            server._strict_identity_json(b'{"protocol":"pair-identity-v3"}'),
            {"protocol": "pair-identity-v3"},
        )

        state = self.session()
        legacy = server.PairingSession(invitation=INV, expires_at=self.expiry)
        httpd = ThreadingHTTPServer(
            ("127.0.0.1", 0), server.make_handler(legacy, state),
        )
        worker = threading.Thread(target=httpd.serve_forever, daemon=True)
        worker.start()

        def bad_post(body, extra_headers=()):
            conn = http.client.HTTPConnection(
                "127.0.0.1", httpd.server_port, timeout=3,
            )
            try:
                conn.putrequest("POST", "/v3/identity-begin")
                conn.putheader("Content-Type", "application/json")
                conn.putheader("Content-Length", str(len(body)))
                for header, value in extra_headers:
                    conn.putheader(header, value)
                conn.endheaders(body)
                response = conn.getresponse()
                response.read()
                return response.status
            finally:
                conn.close()

        try:
            values = {
                "protocol": v3.PROTOCOL, "invitation": INV,
                "phone_fp": self.phone_fp, "phone_nonce": PHONE_NONCE,
            }
            valid_json = json.dumps(values).encode()
            duplicate = (
                b'{"protocol":"pair-identity-v3",'
                b'"protocol":"pair-identity-v3",'
                b'"invitation":"' + INV.encode() + b'",'
                b'"phone_fp":"' + self.phone_fp.encode() + b'",'
                b'"phone_nonce":"' + PHONE_NONCE.encode() + b'"}'
            )
            with mock.patch.object(server, "_ask_pc_user", return_value=True) as approve:
                self.assertEqual(bad_post(duplicate), 403)
                self.assertEqual(bad_post(
                    valid_json, (("Content-Length", str(len(valid_json))),),
                ), 400)
                self.assertEqual(bad_post(
                    valid_json, (("Transfer-Encoding", "chunked"),),
                ), 400)
                approve.assert_not_called()
                self.assertFalse(state.finished.is_set())
                self.assertFalse(legacy.claimed)

                request = urllib.request.Request(
                    "http://127.0.0.1:" + str(httpd.server_port)
                    + "/v3/identity-begin", data=valid_json,
                    headers={"Content-Type": "application/json"},
                )
                with urllib.request.urlopen(request, timeout=4) as response:
                    begin = json.load(response)
                self.assertEqual(begin["status"], "challenge")
                approve.assert_called_once_with(PHONE_NONCE)
                self.assertFalse(legacy.claimed)
        finally:
            httpd.shutdown()
            httpd.server_close()
            worker.join(timeout=2)

    def test_requires_explicit_cli_flags_and_no_network_identity_side_effects(self):
        self.assertEqual(companion.main(["--identity-pair"]), 2)
        self.assertEqual(companion.main(["--start", "--identity-pair"]), 2)
        self.assertEqual(companion.main(["--start", "--pair", "--identity-pair"]), 2)
        self.assertEqual(companion.main(["--identity-create", "--identity-pair"]), 2)
        self.assertEqual(companion.main([]), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)

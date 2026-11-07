"""NETLAB-03B-4B-1: PC QR-v3 opt-in protocol, permission and replay tests.

The loopback HTTP handler tests have no TLS; production uses pinned, private-LAN
TLS from pairing_server.run_pairing. No Android v3 app client is shipped yet.
"""
from __future__ import annotations

import base64
import hashlib
import json
from http.server import ThreadingHTTPServer
from pathlib import Path
import sys
import threading
import time
import unittest
import urllib.error
import urllib.request
from unittest import mock

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "examples" / "windows_companion"))

from identity_proof import _sign_with_key, verify_identity_proof  # noqa: E402
from proof_pairing_transport import (  # noqa: E402
    QrProofSession, make_qr_proof_handler,
    pc_comparison_code, verified_android_fingerprint,
)
import companion  # noqa: E402
import pairing_server as pairing  # noqa: E402

INV = "a" * 32
TLS = "b" * 64


def spki(key):
    return key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo,
    )


def fingerprint(key):
    return hashlib.sha256(spki(key)).hexdigest()


def create_session(pc_key=None, android_key=None, approve=None, expires=None):
    pc_key = pc_key or ec.generate_private_key(ec.SECP256R1())
    android_key = android_key or ec.generate_private_key(ec.SECP256R1())
    if approve is None:
        approve = lambda _code: True
    expiry = int(time.time()) + 120 if expires is None else expires

    def sign_pc(**fields):
        return _sign_with_key(pc_key, role="pc", **fields)

    return QrProofSession(
        invitation=INV, tls_fingerprint=TLS,
        pc_fingerprint=fingerprint(pc_key), expires_at=expiry,
        ask_pc_user=approve, sign_pc=sign_pc,
    ), pc_key, android_key


def begin_request(android_key, nonce="c" * 64):
    return {
        "protocol": "pair-proof-v3",
        "invitation": INV,
        "phone_nonce": nonce,
        "android_spki": base64.b64encode(spki(android_key)).decode("ascii"),
    }


def finish_request(pc_key, android_key, response, approved=True):
    fields = dict(
        role="android", invitation=INV, tls_fingerprint=TLS,
        peer_fingerprint=fingerprint(pc_key),
        nonce=response["pc_nonce"], expires_at=response["expires_at"],
    )
    return {
        "protocol": "pair-proof-v3",
        "invitation": INV,
        "phone_approved": approved,
        "android_proof": _sign_with_key(android_key, **fields),
    }


class ProofWireTests(unittest.TestCase):
    def test_qr_v3_is_distinct_from_v2_and_has_both_pins(self):
        v2 = pairing.invite_payload(
            "192.168.1.7", 50500, TLS, INV, 1800000000,
        )
        self.assertEqual(v2.count("v2?"), 1)
        v3 = pairing.invite_payload(
            "192.168.1.7", 50500, TLS, INV, 1800000000,
            identity_fingerprint="d" * 64,
        )
        self.assertEqual(
            v3,
            v2.replace("v2?", "v3?") + "&id=" + "d" * 64,
        )
        self.assertNotIn("private", v3)
        for invalid in ("d" * 63, "Z" * 64, "", "d" * 65):
            with self.assertRaises(ValueError):
                pairing.invite_payload(
                    "192.168.1.7", 50500, TLS, INV, 1800000000,
                    identity_fingerprint=invalid,
                )

    def test_local_mutual_signature_flow_requires_both_keys(self):
        state, pc, phone = create_session()
        start = begin_request(phone)
        answer = state.begin(start)
        self.assertEqual(answer["status"], "challenge")
        self.assertEqual(answer["protocol"], "pair-proof-v3")
        self.assertEqual(answer["pc_fingerprint"], fingerprint(pc))
        self.assertEqual(len(answer["pc_nonce"]), 64)
        self.assertNotEqual(answer["pc_nonce"], start["phone_nonce"])
        self.assertTrue(verify_identity_proof(
            answer["pc_proof"],
            expected_signer_fingerprint=fingerprint(pc),
            role="pc", invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=fingerprint(phone),
            nonce=start["phone_nonce"], expires_at=answer["expires_at"],
        ))
        result = state.finish(finish_request(pc, phone, answer))
        self.assertEqual(result, {
            "status": "verified", "protocol": "pair-proof-v3",
        })
        self.assertTrue(state.finished.is_set())
        with self.assertRaises(ValueError):
            state.finish(finish_request(pc, phone, answer))
        with self.assertRaises(ValueError):
            state.begin(start)

    def test_wrong_secret_and_replayed_proof_cannot_complete(self):
        state, pc, phone = create_session()
        start = begin_request(phone)
        answer = state.begin(start)
        attacker = ec.generate_private_key(ec.SECP256R1())
        bad = finish_request(pc, attacker, answer)
        with self.assertRaises(ValueError):
            state.finish(bad)
        self.assertTrue(state.finished.is_set())
        with self.assertRaises(ValueError):
            state.finish(finish_request(pc, phone, answer))

        state2, pc2, phone2 = create_session(pc_key=pc, android_key=phone)
        start2 = begin_request(phone2)
        answer2 = state2.begin(start2)
        # Another session has an independent PC-issued nonce.
        wrong = finish_request(pc, phone, answer)
        with self.assertRaises(ValueError):
            state2.finish(wrong)

    def test_missing_consent_expiry_and_reflection_are_rejected(self):
        declined, pc, phone = create_session(approve=lambda _code: False)
        with self.assertRaises(ValueError):
            declined.begin(begin_request(phone))
        self.assertTrue(declined.finished.is_set())

        state, pc, phone = create_session()
        answer = state.begin(begin_request(phone))
        with self.assertRaises(ValueError):
            state.finish(finish_request(pc, phone, answer, approved=False))
        self.assertTrue(state.finished.is_set())

        expired, pc, phone = create_session(expires=int(time.time()) - 1)
        with self.assertRaises(ValueError):
            expired.begin(begin_request(phone))
        self.assertFalse(expired.finished.is_set())  # no valid claim was made

        state, pc, phone = create_session()
        answer = state.begin(begin_request(phone))
        pc_role_proof = answer["pc_proof"]
        wrong = finish_request(pc, phone, answer)
        wrong["android_proof"] = pc_role_proof
        with self.assertRaises(ValueError):
            state.finish(wrong)

    def test_bad_spki_nonce_invitation_rejected_before_pc_prompt(self):
        calls = []
        state, _pc, phone = create_session(approve=lambda code: calls.append(code) or True)
        for tweak in (
            {"phone_nonce": "x" * 64},
            {"invitation": "f" * 32},
            {"android_spki": "not-base64!"},
            {"android_spki": base64.b64encode(b"not DER").decode()},
            {"unexpected": True},
            {"protocol": "pair-qr-v2"},
        ):
            value = begin_request(phone)
            value.update(tweak)
            with self.subTest(tweak=tweak), self.assertRaises(ValueError):
                state.begin(value)
        self.assertEqual(calls, [])
        self.assertFalse(state.finished.is_set())
        state.cancel()
        self.assertTrue(state.finished.is_set())

    def test_identity_parser_and_code_vector(self):
        _, pc, phone = create_session()
        identity = base64.b64encode(spki(phone)).decode()
        self.assertEqual(verified_android_fingerprint(identity), fingerprint(phone))
        self.assertEqual(pc_comparison_code("c" * 64), hashlib.sha256(bytes.fromhex("c" * 64)).hexdigest()[:6].upper())
        with self.assertRaises(ValueError):
            verified_android_fingerprint("!!")

    def test_explicit_cli_flag_does_not_start_without_all_opt_ins(self):
        with mock.patch.object(companion, "run_beacon") as beacon:
            self.assertEqual(companion.main(["--identity-qr"]), 2)
            self.assertEqual(companion.main(["--start", "--identity-qr"]), 2)
            self.assertEqual(companion.main(["--start", "--pair", "--identity-qr"]), 2)
            beacon.assert_not_called()
        self.assertEqual(companion.main([]), 0)

    def test_legacy_v2_handler_refuses_new_v3_endpoint(self):
        session = pairing.PairingSession(invitation=INV, expires_at=time.time() + 120)
        server = ThreadingHTTPServer(
            ("127.0.0.1", 0), pairing.make_handler(session),
        )
        t = threading.Thread(target=server.serve_forever, daemon=True)
        t.start()
        try:
            with self.assertRaises(urllib.error.HTTPError) as error:
                self._post(server.server_port, "/v3/proof-begin", {})
            self.assertEqual(error.exception.code, 404)
        finally:
            server.shutdown()
            server.server_close()
            t.join(timeout=2)

    def test_loopback_post_protocol_and_single_use(self):
        state, pc, phone = create_session()
        server = ThreadingHTTPServer(
            ("127.0.0.1", 0), make_qr_proof_handler(state),
        )
        t = threading.Thread(target=server.serve_forever, daemon=True)
        t.start()
        try:
            with self._post(server.server_port, "/v3/proof-begin", begin_request(phone)) as r:
                self.assertEqual(r.status, 200)
                self.assertEqual(r.headers["Cache-Control"], "no-store")
                answer = json.load(r)
            with self._post(
                server.server_port, "/v3/proof-finish",
                finish_request(pc, phone, answer),
            ) as r:
                self.assertEqual(json.load(r)["status"], "verified")
            with self.assertRaises(urllib.error.HTTPError) as replay:
                self._post(server.server_port, "/v3/proof-finish", finish_request(pc, phone, answer))
            self.assertEqual(replay.exception.code, 403)
            self.assertTrue(state.finished.is_set())
        finally:
            server.shutdown()
            server.server_close()
            t.join(timeout=2)

    @staticmethod
    def _post(port, path, payload):
        request = urllib.request.Request(
            f"http://127.0.0.1:{port}{path}",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        return urllib.request.urlopen(request, timeout=4)


if __name__ == "__main__":
    unittest.main(verbosity=2)

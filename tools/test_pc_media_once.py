"""R6A signed media authorization tests with mock executor; NOT device QA."""
from __future__ import annotations
import hashlib
import sys
import time
import unittest
from pathlib import Path
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "examples/windows_companion"))
import companion
import identity_pairing_v3 as v3
import identity_proof as proof
import pairing_server as server
from media_control_once import COMMAND_KEYS, MediaOnceAttempt, PROTOCOL, scoped_nonce, execute_windows_media_key

INV, TLS, NONCE = "a" * 32, "b" * 64, "c" * 64


def fingerprint(key):
    der = key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    return hashlib.sha256(der).hexdigest()


class MediaOnceTests(unittest.TestCase):
    def setUp(self):
        self.pc = ec.generate_private_key(ec.SECP256R1())
        self.phone = ec.generate_private_key(ec.SECP256R1())
        self.pc_fp, self.phone_fp = fingerprint(self.pc), fingerprint(self.phone)
        self.expires = int(time.time()) + 240
        pc_sign = lambda **k: proof._sign_with_key(self.pc, role="pc", **k)
        self.identity = v3.IdentityPairingAttempt(
            invitation=INV, qr_expires=self.expires,
            tls_fingerprint=TLS, pc_fingerprint=self.pc_fp, signer=pc_sign)
        self.executed = []
        self.media = MediaOnceAttempt(
            identity=self.identity, invitation=INV, qr_expires=self.expires,
            tls_fingerprint=TLS, pc_fingerprint=self.pc_fp,
            signer=pc_sign, executor=self.executed.append)

    def authenticate(self):
        first = self.identity.begin(
            invitation=INV, phone_fingerprint=self.phone_fp,
            phone_nonce=NONCE, approve_on_pc=lambda _: True)
        signed = proof._sign_with_key(
            self.phone, role="android", invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=self.pc_fp, nonce=first["pc_nonce"],
            expires_at=first["expires"])
        self.assertEqual("approved", self.identity.finish(
            invitation=INV, phone_fingerprint=self.phone_fp,
            phone_proof=signed)["status"])

    def begin(self, command="volume_up", approve=lambda _: True):
        return self.media.begin(
            invitation=INV, phone_fp=self.phone_fp, phone_nonce=NONCE,
            command=command, approve_pc_media=approve)

    def phone_proof(self, first, command="volume_up", scoped=True):
        return proof._sign_with_key(
            self.phone, role="android", invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=self.pc_fp,
            nonce=scoped_nonce(first["pc_nonce"], command) if scoped else first["pc_nonce"],
            expires_at=first["expires"])

    def test_no_media_before_two_distinct_consents(self):
        with self.assertRaises(ValueError):
            self.begin()
        self.authenticate()
        with self.assertRaises(PermissionError):
            self.begin(approve=lambda _: False)
        self.assertEqual([], self.executed)
        self.assertTrue(self.media.finished.is_set())

    def test_one_action_proof_and_replay(self):
        self.authenticate()
        challenge = self.begin()
        self.assertEqual(PROTOCOL, challenge["protocol"])
        self.assertTrue(proof.verify_identity_proof(
            challenge["pc_proof"], expected_signer_fingerprint=self.pc_fp,
            role="pc", invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=self.phone_fp,
            nonce=scoped_nonce(NONCE, "volume_up"), expires_at=challenge["expires"]))
        result = self.media.finish(
            invitation=INV, phone_fp=self.phone_fp, phone_proof=self.phone_proof(challenge))
        self.assertEqual("executed", result["status"])
        self.assertEqual(["volume_up"], self.executed)
        with self.assertRaises(PermissionError):
            self.media.finish(
                invitation=INV, phone_fp=self.phone_fp, phone_proof=self.phone_proof(challenge))
        self.assertEqual(["volume_up"], self.executed)

    def test_different_action_or_identity_nonce_fails_closed(self):
        self.authenticate()
        with self.assertRaises(ValueError):
            self.begin(command="cmd /c whoami", approve=lambda _: self.fail("prompt"))
        challenge = self.begin()
        with self.assertRaises(ValueError):
            self.media.finish(invitation=INV, phone_fp=self.phone_fp,
                              phone_proof=self.phone_proof(challenge, "volume_down"))
        self.assertEqual([], self.executed)
        self.assertTrue(self.media.finished.is_set())

    def test_identity_signature_not_usable_for_action(self):
        self.authenticate()
        challenge = self.begin()
        with self.assertRaises(ValueError):
            self.media.finish(invitation=INV, phone_fp=self.phone_fp,
                              phone_proof=self.phone_proof(challenge, scoped=False))
        self.assertEqual([], self.executed)

    def test_arbitrary_key_never_executes(self):
        self.assertEqual(4, len(COMMAND_KEYS))
        with self.assertRaises(ValueError):
            execute_windows_media_key("shell")
        with self.assertRaises(ValueError):
            scoped_nonce("a" * 64, "type_text")


if __name__ == "__main__":
    unittest.main()

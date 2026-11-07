"""NETLAB-03B-3: offline P-256 role/context proof tests (no pairing listener)."""
from __future__ import annotations

import base64
import hashlib
import os
from pathlib import Path
import sys
import tempfile
import unittest

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "examples" / "windows_companion"))

import identity_proof as proof  # noqa: E402
import windows_identity  # noqa: E402

INV = "a" * 32
TLS = "b" * 64
PEER = "c" * 64
NONCE = "d" * 64
EXPIRY = 2000000000
NOW = EXPIRY - 120


def args(role: str = "pc") -> dict:
    return dict(
        role=role, invitation=INV, tls_fingerprint=TLS,
        peer_fingerprint=PEER, nonce=NONCE, expires_at=EXPIRY,
    )


def fingerprint(key: ec.EllipticCurvePrivateKey) -> str:
    spki = key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return hashlib.sha256(spki).hexdigest()


class ProofTests(unittest.TestCase):
    def setUp(self):
        self.key = ec.generate_private_key(ec.SECP256R1())
        self.response = proof._sign_with_key(self.key, **args())
        self.expected = fingerprint(self.key)

    def verify(self, response=None, **changed):
        values = args()
        values.update(changed)
        return proof.verify_identity_proof(
            self.response if response is None else response,
            expected_signer_fingerprint=self.expected,
            now_epoch_seconds=NOW, **values,
        )

    def test_canonical_interop_vector(self):
        expected = (
            "CHAPPY-NETLAB-03B-PROOF-V1\n"
            "role=pc\n"
            "invitation=" + INV + "\n"
            "tls=" + TLS + "\n"
            "peer=" + PEER + "\n"
            "nonce=" + NONCE + "\n"
            "expires=" + str(EXPIRY) + "\n"
        ).encode("ascii")
        self.assertEqual(proof.canonical_challenge(**args()), expected)

    def test_proof_is_bound_to_one_role_and_every_session_field(self):
        self.assertTrue(self.verify())
        for altered in [
            dict(role="android"), dict(invitation="f" * 32),
            dict(tls_fingerprint="e" * 64), dict(peer_fingerprint="f" * 64),
            dict(nonce="1" * 64), dict(expires_at=EXPIRY - 1),
        ]:
            with self.subTest(altered=altered):
                self.assertFalse(self.verify(**altered))

    def test_android_role_can_be_verified_by_same_contract(self):
        android = proof._sign_with_key(self.key, **args(role="android"))
        self.assertTrue(self.verify(android, role="android"))
        self.assertFalse(self.verify(android, role="pc"))

    def test_wrong_public_identity_and_tampering_fail_closed(self):
        wrong = fingerprint(ec.generate_private_key(ec.SECP256R1()))
        self.assertFalse(proof.verify_identity_proof(
            self.response, expected_signer_fingerprint=wrong,
            now_epoch_seconds=NOW, **args(),
        ))
        modified = dict(self.response)
        modified["signature"] = base64.b64encode(b"garbage").decode()
        self.assertFalse(self.verify(modified))
        for field, value in [
            ("algorithm", "P-384"), ("spki", "not base64!"),
            ("signature", "x" * 1000), ("private_key", "SHOULD NOT EXIST"),
        ]:
            modified = dict(self.response)
            modified[field] = value
            self.assertFalse(self.verify(modified))

    def test_expiry_and_input_validation(self):
        self.assertFalse(proof.verify_identity_proof(
            self.response, expected_signer_fingerprint=self.expected,
            now_epoch_seconds=EXPIRY + 1, **args(),
        ))
        self.assertFalse(proof.verify_identity_proof(
            self.response, expected_signer_fingerprint=self.expected,
            now_epoch_seconds=EXPIRY - 601, **args(),
        ))
        for invalid in [
            dict(role="server"), dict(invitation="a" * 31),
            dict(tls_fingerprint="B" * 64), dict(nonce="d" * 63),
            dict(expires_at=True),
        ]:
            data = args()
            data.update(invalid)
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                proof.canonical_challenge(**data)

    @unittest.skipUnless(os.name == "nt", "Real Windows DPAPI requires Windows CI")
    def test_pc_dpapi_signing_revoke_and_missing_key(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            with self.assertRaises(FileNotFoundError):
                proof.sign_pc_challenge(directory=folder, **{
                    k: v for k, v in args().items() if k != "role"
                })
            pc_fp = windows_identity.create_identity(folder)
            signed = proof.sign_pc_challenge(directory=folder, **{
                k: v for k, v in args().items() if k != "role"
            })
            self.assertTrue(proof.verify_identity_proof(
                signed, expected_signer_fingerprint=pc_fp,
                now_epoch_seconds=NOW, **args(),
            ))
            windows_identity.revoke_identity(folder)
            with self.assertRaises(FileNotFoundError):
                proof.sign_pc_challenge(directory=folder, **{
                    k: v for k, v in args().items() if k != "role"
                })


if __name__ == "__main__":
    unittest.main(verbosity=2)

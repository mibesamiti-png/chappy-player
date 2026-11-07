"""NETLAB-03B-4A: no-network bilateral proof lifecycle tests."""
from __future__ import annotations

import concurrent.futures
import hashlib
from pathlib import Path
import sys
import unittest

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "examples" / "windows_companion"))

from identity_proof import _sign_with_key  # noqa: E402
from mutual_proof_session import MutualProofSession  # noqa: E402

NOW = 1800000000
EXP = NOW + 120
INV = "a" * 32
TLS = "b" * 64


def fingerprint(key):
    encoded = key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return hashlib.sha256(encoded).hexdigest()


class MutualProofSessionTest(unittest.TestCase):
    def setUp(self):
        self.pc = ec.generate_private_key(ec.SECP256R1())
        self.android = ec.generate_private_key(ec.SECP256R1())
        self.pc_fp = fingerprint(self.pc)
        self.android_fp = fingerprint(self.android)
        self.session = self.new_session()

    def new_session(self):
        return MutualProofSession(
            invitation=INV, tls_fingerprint=TLS,
            pc_fingerprint=self.pc_fp, android_fingerprint=self.android_fp,
            expires_at=EXP, now_epoch_seconds=NOW,
        )

    def signed(self, signer, request):
        key = self.pc if signer == "pc" else self.android
        return _sign_with_key(key, **vars(request))

    def both_proofs(self, session=None):
        session = session or self.session
        android = session.pc_issued_request_for_android
        pc = session.android_issued_request_for_pc
        self.assertEqual(android.role, "android")
        self.assertEqual(pc.role, "pc")
        self.assertNotEqual(android.nonce, pc.nonce)
        self.assertTrue(session.submit_proof(
            signer="android", response=self.signed("android", android),
            now_epoch_seconds=NOW,
        ))
        self.assertTrue(session.submit_proof(
            signer="pc", response=self.signed("pc", pc),
            now_epoch_seconds=NOW,
        ))

    def test_both_proofs_and_approvals_one_success_only(self):
        self.both_proofs()
        self.assertTrue(self.session.approve(
            side="pc", approved=True, now_epoch_seconds=NOW,
        ))
        self.assertTrue(self.session.approve(
            side="android", approved=True, now_epoch_seconds=NOW,
        ))
        self.assertTrue(self.session.complete(now_epoch_seconds=NOW))
        self.assertFalse(self.session.complete(now_epoch_seconds=NOW))
        self.assertFalse(self.session.approve(
            side="pc", approved=True, now_epoch_seconds=NOW,
        ))

    def test_one_sided_proof_cannot_complete(self):
        req = self.session.pc_issued_request_for_android
        self.assertTrue(self.session.submit_proof(
            signer="android", response=self.signed("android", req),
            now_epoch_seconds=NOW,
        ))
        self.assertFalse(self.session.complete(now_epoch_seconds=NOW))
        self.assertFalse(self.session.submit_proof(
            signer="pc", response=self.signed(
                "pc", self.session.android_issued_request_for_pc,
            ), now_epoch_seconds=NOW,
        ))

    def test_reflection_crossed_nonce_wrong_key_and_replay_fail(self):
        for attack in ("reflection", "crossed", "wrong_key", "replay"):
            session = self.new_session()
            req = session.pc_issued_request_for_android
            if attack == "reflection":
                response = self.signed("pc", session.android_issued_request_for_pc)
            elif attack == "crossed":
                response = self.signed("android", session.android_issued_request_for_pc)
            elif attack == "wrong_key":
                response = self.signed("pc", req)
            else:
                other = self.new_session()
                response = self.signed("android", other.pc_issued_request_for_android)
            self.assertFalse(session.submit_proof(
                signer="android", response=response, now_epoch_seconds=NOW,
            ), attack)
            self.assertFalse(session.complete(now_epoch_seconds=NOW))

    def test_repeated_proof_aborts_entire_attempt(self):
        req = self.session.pc_issued_request_for_android
        response = self.signed("android", req)
        self.assertTrue(self.session.submit_proof(
            signer="android", response=response, now_epoch_seconds=NOW,
        ))
        self.assertFalse(self.session.submit_proof(
            signer="android", response=response, now_epoch_seconds=NOW,
        ))
        self.assertFalse(self.session.complete(now_epoch_seconds=NOW))

    def test_reject_and_cancel_fail_closed(self):
        for side in ("pc", "android"):
            session = self.new_session()
            self.both_proofs(session)
            self.assertFalse(session.approve(
                side=side, approved=False, now_epoch_seconds=NOW,
            ))
            self.assertFalse(session.complete(now_epoch_seconds=NOW))
        session = self.new_session()
        self.both_proofs(session)
        session.cancel()
        self.assertFalse(session.complete(now_epoch_seconds=NOW))

    def test_approval_requires_both_crypto_proofs(self):
        self.assertFalse(self.session.approve(
            side="pc", approved=True, now_epoch_seconds=NOW,
        ))
        self.assertFalse(self.session.complete(now_epoch_seconds=NOW))

    def test_expiry_and_invalid_configuration(self):
        session = self.new_session()
        self.both_proofs(session)
        self.assertFalse(session.approve(
            side="pc", approved=True, now_epoch_seconds=EXP,
        ))
        for values in (
            {"expires_at": NOW}, {"expires_at": NOW + 601},
            {"pc_fingerprint": "BAD"}, {"android_fingerprint": self.pc_fp},
        ):
            kwargs = dict(
                invitation=INV, tls_fingerprint=TLS,
                pc_fingerprint=self.pc_fp, android_fingerprint=self.android_fp,
                expires_at=EXP, now_epoch_seconds=NOW,
            )
            kwargs.update(values)
            with self.assertRaises(ValueError):
                MutualProofSession(**kwargs)

    def test_simultaneous_replay_only_one_attempt_can_pass(self):
        req = self.session.pc_issued_request_for_android
        response = self.signed("android", req)

        def attempt(_):
            return self.session.submit_proof(
                signer="android", response=response, now_epoch_seconds=NOW,
            )

        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(attempt, range(8)))
        self.assertEqual(results.count(True), 1)
        self.assertEqual(results.count(False), 7)
        self.assertFalse(self.session.complete(now_epoch_seconds=NOW))

    def test_no_network_side_effects_from_creation(self):
        self.assertEqual(len(self.session.pc_issued_request_for_android.nonce), 64)
        self.assertEqual(len(self.session.android_issued_request_for_pc.nonce), 64)
        self.assertFalse(self.session.complete(now_epoch_seconds=NOW))


if __name__ == "__main__":
    unittest.main(verbosity=2)

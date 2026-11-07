"""Windows DPAPI verification-history regression and QR-v3 result isolation.

All on-disk tests run with temporary directories under the Windows CI user.
On non-Windows hosts, verify that DPAPI history is unavailable by design.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "examples" / "windows_companion"))

import companion  # noqa: E402
import identity_pairing_v3 as v3  # noqa: E402
import identity_proof as proof  # noqa: E402
import verified_phone_history as history  # noqa: E402
import windows_identity as pc  # noqa: E402

from cryptography.hazmat.primitives import serialization  # noqa: E402
from cryptography.hazmat.primitives.asymmetric import ec  # noqa: E402

INV = "a" * 32
TLS = "b" * 64
NONCE = "c" * 64


def fingerprint(key):
    public = key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return hashlib.sha256(public).hexdigest()


class VerifiedHistoryTests(unittest.TestCase):
    def test_dpapi_is_windows_only_and_no_read_creates_identity(self):
        if os.name == "nt":
            self.skipTest("Real DPAPI fixtures run below on Windows")
        with self.assertRaises(OSError):
            history.list_verified_phones()
        with mock.patch("builtins.input", return_value="no") as inp:
            self.assertFalse(history.offer_remember_verified_phone("e" * 64))
            inp.assert_called_once()

    def test_fingerprint_validation_and_quiet_denial(self):
        for bad in ("", "X" * 64, "abc", "0" * 65, "F" * 32, 5):
            with self.subTest(value=bad), self.assertRaises(ValueError):
                history.offer_remember_verified_phone(bad)
        with mock.patch("builtins.input", return_value="NO") as inp, \
             mock.patch.object(history, "remember_verified_phone") as save:
            self.assertFalse(history.offer_remember_verified_phone("d" * 64))
            inp.assert_called_once()
            save.assert_not_called()
        with mock.patch("builtins.input", side_effect=EOFError), \
             mock.patch.object(history, "remember_verified_phone") as save:
            self.assertFalse(history.offer_remember_verified_phone("d" * 64))
            save.assert_not_called()

    def test_only_valid_two_way_proof_exposes_recordable_phone(self):
        key_pc = ec.generate_private_key(ec.SECP256R1())
        key_phone = ec.generate_private_key(ec.SECP256R1())
        pc_fp = fingerprint(key_pc)
        phone_fp = fingerprint(key_phone)
        def signer(**kwargs):
            return proof._sign_with_key(key_pc, role="pc", **kwargs)
        def new_session():
            return v3.IdentityPairingAttempt(
                invitation=INV, qr_expires=int(time.time()) + 240,
                tls_fingerprint=TLS, pc_fingerprint=pc_fp, signer=signer,
            )
        session = new_session()
        self.assertIsNone(session.verified_phone_fingerprint)
        begin = session.begin(
            invitation=INV, phone_fingerprint=phone_fp, phone_nonce=NONCE,
            approve_on_pc=lambda _: True,
        )
        self.assertIsNone(session.verified_phone_fingerprint)
        signature = proof._sign_with_key(
            key_phone, role="android", invitation=INV,
            tls_fingerprint=TLS, peer_fingerprint=pc_fp,
            nonce=begin["pc_nonce"], expires_at=begin["expires"],
        )
        approved = session.finish(
            invitation=INV, phone_fingerprint=phone_fp,
            phone_proof=signature,
        )
        self.assertEqual(approved["status"], "approved")
        self.assertEqual(session.verified_phone_fingerprint, phone_fp)
        with self.assertRaises(ValueError):
            session.finish(
                invitation=INV, phone_fingerprint=phone_fp,
                phone_proof=signature,
            )
        self.assertEqual(session.verified_phone_fingerprint, phone_fp)

        for kind in ("denial", "tamper", "expiry"):
            with self.subTest(kind=kind):
                other = new_session()
                if kind == "denial":
                    with self.assertRaises(PermissionError):
                        other.begin(
                            invitation=INV, phone_fingerprint=phone_fp,
                            phone_nonce=NONCE, approve_on_pc=lambda _: False,
                        )
                else:
                    started = other.begin(
                        invitation=INV, phone_fingerprint=phone_fp,
                        phone_nonce=NONCE, approve_on_pc=lambda _: True,
                    )
                    challenge = proof._sign_with_key(
                        key_phone, role="android", invitation=INV,
                        tls_fingerprint=TLS, peer_fingerprint=pc_fp,
                        nonce=started["pc_nonce"], expires_at=started["expires"],
                    )
                    if kind == "tamper":
                        challenge["signature"] = "invalid!"
                        with self.assertRaises(ValueError):
                            other.finish(
                                invitation=INV, phone_fingerprint=phone_fp,
                                phone_proof=challenge,
                            )
                    else:
                        with mock.patch.object(v3.time, "time",
                                              return_value=started["expires"]):
                            with self.assertRaises(ValueError):
                                other.finish(
                                    invitation=INV, phone_fingerprint=phone_fp,
                                    phone_proof=challenge,
                                )
                self.assertIsNone(other.verified_phone_fingerprint)

    @unittest.skipUnless(os.name == "nt", "Windows Crypt32 DPAPI required")
    def test_encrypted_save_list_dedupe_forget_revoke_and_rotation(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "current-user"
            self.assertRegex(pc.create_identity(folder), r"^[0-9a-f]{64}$")
            self.assertEqual(history.list_verified_phones(folder), [])
            file = folder / history.HISTORY_FILENAME
            self.assertFalse(file.exists())
            first, second = "a" * 64, "b" * 64
            self.assertTrue(history.remember_verified_phone(first, folder))
            ciphertext = file.read_bytes()
            self.assertNotIn(first.encode(), ciphertext)
            self.assertNotIn(history.PREFIX, ciphertext)
            self.assertLess(len(ciphertext), history.MAX_BLOB + 1)
            self.assertFalse(history.remember_verified_phone(first, folder))
            self.assertEqual(file.read_bytes(), ciphertext)
            self.assertTrue(history.remember_verified_phone(second, folder))
            listed = history.list_verified_phones(folder)
            self.assertEqual([v["fingerprint"] for v in listed], [first, second])
            self.assertTrue(all(type(v["verified_at"]) is int for v in listed))
            self.assertFalse(history.forget_verified_phone("c" * 64, folder))
            self.assertTrue(history.forget_verified_phone(first, folder))
            self.assertEqual(len(history.list_verified_phones(folder)), 1)
            self.assertTrue(pc.revoke_identity(folder))
            self.assertFalse(file.exists())
            self.assertIsNone(pc.identity_status(folder))
            with self.assertRaises(ValueError):
                history.remember_verified_phone(first, folder)
            new_owner = pc.create_identity(folder)
            self.assertRegex(new_owner, r"^[0-9a-f]{64}$")
            self.assertEqual(history.list_verified_phones(folder), [])

    @unittest.skipUnless(os.name == "nt", "Windows Crypt32 DPAPI required")
    def test_tampering_and_mismatched_owner_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            first_owner = pc.create_identity(folder)
            history.remember_verified_phone("f" * 64, folder)
            file = folder / history.HISTORY_FILENAME
            original = file.read_bytes()
            corrupted = bytearray(original)
            corrupted[len(corrupted) // 2] ^= 0x40
            file.write_bytes(corrupted)
            with self.assertRaises((OSError, ValueError)):
                history.list_verified_phones(folder)
            file.write_bytes(original)

            # Force owner mismatch without using an actual old key; no silent
            # reuse of a history after PC identity rotation.
            clear = history.PREFIX + (
                '{"schema":1,"owner":"' + ("0" * 64) + '","records":[]}'
            ).encode()
            file.write_bytes(pc._dpapi(clear, protect=True))
            self.assertNotEqual(first_owner, "0" * 64)
            with self.assertRaises(ValueError):
                history.list_verified_phones(folder)

            # Reject ambiguous JSON with duplicate keys before field parsing.
            bad = history.PREFIX + (
                '{"schema":1,"schema":1,"owner":"' + first_owner
                + '","records":[]}'
            ).encode()
            file.write_bytes(pc._dpapi(bad, protect=True))
            with self.assertRaises(ValueError):
                history.list_verified_phones(folder)

            # Removing the local PC identity clears corrupt history too.
            self.assertTrue(pc.revoke_identity(folder))
            self.assertFalse(file.exists())

    @unittest.skipUnless(os.name == "nt", "Windows Crypt32 DPAPI required")
    def test_atomic_write_failure_keeps_existing_ciphertext(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            pc.create_identity(folder)
            history.remember_verified_phone("d" * 64, folder)
            file = folder / history.HISTORY_FILENAME
            before = file.read_bytes()
            with mock.patch.object(history.os, "replace",
                                   side_effect=OSError("simulated crash")):
                with self.assertRaises(OSError):
                    history.remember_verified_phone("e" * 64, folder)
            self.assertEqual(file.read_bytes(), before)
            self.assertEqual(list(folder.glob(".verified-phone-*")), [])

    @unittest.skipUnless(os.name == "nt", "Windows local-only CLI checks")
    def test_cli_history_explicit_forget_and_no_listener(self):
        with tempfile.TemporaryDirectory() as tmp, \
             mock.patch.dict(os.environ, {"LOCALAPPDATA": tmp}), \
             mock.patch.object(companion, "run_beacon") as beacon:
            folder = Path(tmp) / "ChappyCompanion"
            self.assertEqual(companion.main(["--identity-create"]), 0)
            self.assertEqual(companion.main(["--verified-list"]), 0)
            history.remember_verified_phone("f" * 64, folder)
            self.assertEqual(companion.main(["--verified-list"]), 0)
            self.assertEqual(companion.main(["--verified-forget", "X" * 64]), 2)
            with mock.patch("builtins.input", return_value="cancel"):
                self.assertEqual(
                    companion.main(["--verified-forget", "f" * 64]), 2
                )
            self.assertEqual(len(history.list_verified_phones(folder)), 1)
            with mock.patch("builtins.input", return_value="FORGET"):
                self.assertEqual(
                    companion.main(["--verified-forget", "f" * 64]), 0
                )
            self.assertEqual(history.list_verified_phones(folder), [])
            with self.assertRaises(SystemExit):
                companion.main(["--verified-list", "--start"])
            self.assertEqual(companion.main(["--verified-list", "--pair"]), 2)
            beacon.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)

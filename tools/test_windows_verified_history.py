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
import pairing_server as server  # noqa: E402
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

    def test_clear_cli_requires_exact_consent_and_never_starts_network(self):
        with mock.patch.object(companion, "run_beacon") as beacon, \
             mock.patch.object(history, "clear_verified_phone_history") as clear:
            with mock.patch("builtins.input", return_value="no"):
                self.assertEqual(companion.main(["--verified-clear"]), 2)
            with mock.patch("builtins.input", side_effect=EOFError):
                self.assertEqual(companion.main(["--verified-clear"]), 2)
            clear.assert_not_called()
            with mock.patch("builtins.input", return_value="CLEAR"):
                self.assertEqual(companion.main(["--verified-clear"]), 0)
            clear.assert_called_once_with()
            beacon.assert_not_called()
            with self.assertRaises(SystemExit) as conflicting:
                companion.main(["--verified-clear", "--start"])
            self.assertEqual(conflicting.exception.code, 2)
            self.assertEqual(companion.main(["--verified-clear", "--pair"]), 2)
            self.assertEqual(companion.main(["--verified-clear", "--qr"]), 2)
            self.assertEqual(companion.main(["--verified-clear", "--identity-pair"]), 2)
            beacon.assert_not_called()

    def test_compare_known_phone_requires_explicit_qr_v3_flags(self):
        with mock.patch.object(companion, "run_beacon") as beacon, \
             mock.patch.object(server, "run_pairing") as run, \
             mock.patch.object(history, "select_expected_verified_phone") as choose:
            for args in (
                ["--compare-known-phone"],
                ["--start", "--compare-known-phone"],
                ["--start", "--pair", "--compare-known-phone"],
                ["--start", "--pair", "--qr", "--compare-known-phone"],
                ["--start", "--pair", "--identity-pair", "--compare-known-phone"],
                ["--identity-status", "--compare-known-phone"],
                ["--verified-list", "--compare-known-phone"],
            ):
                with self.subTest(args=args):
                    self.assertEqual(companion.main(args), 2)
            beacon.assert_not_called()
            run.assert_not_called()
            choose.assert_not_called()

    def test_compare_known_phone_cancellation_is_offline(self):
        cli = [
            "--start", "--pair", "--qr", "--identity-pair",
            "--compare-known-phone", "--ip", "192.168.1.7",
        ]
        with mock.patch.object(history, "select_expected_verified_phone",
                               return_value=None) as choose, \
             mock.patch.object(server, "run_pairing") as run, \
             mock.patch.object(companion, "discover_local_ipv4") as discover:
            self.assertEqual(companion.main(cli), 2)
            choose.assert_called_once_with()
            run.assert_not_called()
            discover.assert_not_called()

    @unittest.skipUnless(os.name == "nt", "Windows Crypt32 DPAPI required")
    def test_manual_phone_selector_reads_dpapi_before_listener_and_never_trusts(self):
        cli = [
            "--start", "--pair", "--qr", "--identity-pair",
            "--compare-known-phone", "--ip", "192.168.1.7",
        ]
        with tempfile.TemporaryDirectory() as tmp, \
             mock.patch.dict(os.environ, {"LOCALAPPDATA": tmp}), \
             mock.patch.object(server, "run_pairing") as run, \
             mock.patch.object(companion, "run_beacon") as beacon:
            directory = Path(tmp) / "ChappyCompanion"
            original_identity = pc.create_identity(directory)
            first, second = "d" * 64, "e" * 64
            history.remember_verified_phone(first, directory)
            history.remember_verified_phone(second, directory)
            encrypted = (directory / history.HISTORY_FILENAME).read_bytes()
            with mock.patch("builtins.input", return_value="SELECT 2"):
                self.assertEqual(companion.main(cli), 0)
            run.assert_called_once_with(
                "192.168.1.7", 10, qr=True, identity_mode=True,
                expected_phone_fingerprint=second,
            )
            beacon.assert_not_called()
            self.assertEqual(pc.identity_status(directory), original_identity)
            self.assertEqual(
                (directory / history.HISTORY_FILENAME).read_bytes(), encrypted
            )
            self.assertEqual(len(history.list_verified_phones(directory)), 2)

            run.reset_mock()
            for decline in ("", "2", "select 2", "SELECT 0", "SELECT 25",
                            "SELECT 01", "DELETE", "SELECT 3"):
                with self.subTest(answer=decline), \
                     mock.patch("builtins.input", return_value=decline):
                    self.assertEqual(companion.main(cli), 2)
                run.assert_not_called()
            with mock.patch("builtins.input", side_effect=EOFError):
                self.assertEqual(companion.main(cli), 2)
            run.assert_not_called()
            self.assertEqual(
                (directory / history.HISTORY_FILENAME).read_bytes(), encrypted
            )

    @unittest.skipUnless(os.name == "nt", "Windows Crypt32 DPAPI required")
    def test_missing_or_corrupt_known_phone_history_fails_closed(self):
        cli = [
            "--start", "--pair", "--qr", "--identity-pair",
            "--compare-known-phone", "--ip", "192.168.1.7",
        ]
        with tempfile.TemporaryDirectory() as tmp, \
             mock.patch.dict(os.environ, {"LOCALAPPDATA": tmp}), \
             mock.patch.object(server, "run_pairing") as run, \
             mock.patch.object(companion, "run_beacon") as beacon, \
             mock.patch("builtins.input") as prompt:
            directory = Path(tmp) / "ChappyCompanion"
            pc.create_identity(directory)
            self.assertEqual(companion.main(cli), 1)
            prompt.assert_not_called()
            history.remember_verified_phone("f" * 64, directory)
            (directory / history.HISTORY_FILENAME).write_bytes(b"broken DPAPI")
            self.assertEqual(companion.main(cli), 1)
            run.assert_not_called()
            beacon.assert_not_called()
            prompt.assert_not_called()

    @unittest.skipUnless(os.name == "nt", "Windows Crypt32 DPAPI required")
    def test_clear_keeps_pc_key_and_recovers_corrupt_history(self):
        with tempfile.TemporaryDirectory() as tmp, \
             mock.patch.dict(os.environ, {"LOCALAPPDATA": tmp}), \
             mock.patch.object(companion, "run_beacon") as beacon:
            folder = Path(tmp) / "ChappyCompanion"
            owner = pc.create_identity(folder)
            history.remember_verified_phone("f" * 64, folder)
            file = folder / history.HISTORY_FILENAME
            self.assertTrue(file.exists())
            with mock.patch("builtins.input", return_value="cancel"):
                self.assertEqual(companion.main(["--verified-clear"]), 2)
            self.assertEqual(len(history.list_verified_phones(folder)), 1)
            with mock.patch("builtins.input", return_value="CLEAR"):
                self.assertEqual(companion.main(["--verified-clear"]), 0)
            self.assertFalse(file.exists())
            self.assertEqual(pc.identity_status(folder), owner)
            self.assertEqual(history.list_verified_phones(folder), [])

            history.remember_verified_phone("e" * 64, folder)
            file.write_bytes(b"corrupted ciphertext")
            with self.assertRaises((ValueError, OSError)):
                history.list_verified_phones(folder)
            with mock.patch("builtins.input", return_value="CLEAR"):
                self.assertEqual(companion.main(["--verified-clear"]), 0)
            self.assertEqual(history.list_verified_phones(folder), [])
            self.assertEqual(pc.identity_status(folder), owner)
            beacon.assert_not_called()

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

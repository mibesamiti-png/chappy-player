"""Windows same-user DPAPI P-256 identity tests (real Crypt32 on CI).

On other OSes only the explicit Windows-only denial contract runs.
No private keys, encrypted blobs or real user paths are printed/committed.
"""
from __future__ import annotations

import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "examples" / "windows_companion"))

import companion  # noqa: E402
import windows_identity as identity  # noqa: E402


class PcIdentityTests(unittest.TestCase):
    def test_never_attempt_windows_dpapi_on_other_os(self):
        if os.name == "nt":
            self.skipTest("Real Windows DPAPI tested separately")
        with self.assertRaises(OSError):
            identity.identity_status()

    @unittest.skipUnless(os.name == "nt", "Windows CI exercises real user DPAPI")
    def test_create_status_duplicate_revoke_and_rotation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "private"
            self.assertIsNone(identity.identity_status(root))
            first = identity.create_identity(root)
            self.assertRegex(first, r"^[a-f0-9]{64}$")
            self.assertEqual(identity.identity_status(root), first)
            saved = (root / identity.IDENTITY_FILENAME).read_bytes()
            self.assertGreater(len(saved), 100)
            self.assertNotIn(identity.PLAINTEXT_PREFIX, saved)
            self.assertNotIn(b"BEGIN PRIVATE KEY", saved)

            with self.assertRaises(FileExistsError):
                identity.create_identity(root)
            self.assertEqual((root / identity.IDENTITY_FILENAME).read_bytes(), saved)

            self.assertTrue(identity.revoke_identity(root))
            self.assertIsNone(identity.identity_status(root))
            self.assertFalse(identity.revoke_identity(root))
            second = identity.create_identity(root)
            self.assertNotEqual(first, second)

    @unittest.skipUnless(os.name == "nt", "Windows-only integrity check")
    def test_corruption_is_rejected_and_can_be_recovered_by_explicit_revoke(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            identity.create_identity(root)
            target = root / identity.IDENTITY_FILENAME
            contents = bytearray(target.read_bytes())
            contents[len(contents) // 2] ^= 0x80
            target.write_bytes(contents)
            with self.assertRaises((OSError, ValueError)):
                identity.identity_status(root)
            self.assertTrue(identity.revoke_identity(root))
            self.assertIsNone(identity.identity_status(root))

    def test_cli_identity_commands_never_start_lan_discovery(self):
        with (
            mock.patch.object(companion, "run_beacon") as beacon,
            mock.patch.dict(os.environ, {"LOCALAPPDATA": ""}),
        ):
            # No--start launches no service or hidden identity creation.
            self.assertEqual(companion.main([]), 0)
            beacon.assert_not_called()
            with self.assertRaises(SystemExit) as conflict:
                companion.main(["--identity-create", "--start"])
            self.assertEqual(conflict.exception.code, 2)
            # Network flags are rejected even without --start.
            self.assertEqual(companion.main(["--identity-status", "--pair"]), 2)
            beacon.assert_not_called()

    @unittest.skipUnless(os.name == "nt", "Windows CLI only")
    def test_identity_cli_explicit_revoke_requires_exact_confirmation(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(
            os.environ, {"LOCALAPPDATA": tmp}
        ):
            self.assertEqual(companion.main(["--identity-status"]), 0)
            self.assertEqual(companion.main(["--identity-create"]), 0)
            self.assertEqual(companion.main(["--identity-create"]), 1)
            self.assertEqual(companion.main(["--identity-status"]), 0)
            with mock.patch("builtins.input", return_value="no"):
                self.assertEqual(companion.main(["--identity-revoke"]), 2)
            self.assertIsNotNone(identity.identity_status(
                Path(tmp) / "ChappyCompanion"
            ))
            with mock.patch("builtins.input", return_value="REVOKE"):
                self.assertEqual(companion.main(["--identity-revoke"]), 0)
            self.assertIsNone(identity.identity_status(
                Path(tmp) / "ChappyCompanion"
            ))


if __name__ == "__main__":
    unittest.main(verbosity=2)

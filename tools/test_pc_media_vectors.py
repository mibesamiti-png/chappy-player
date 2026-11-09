"""R6B deterministic cross-language authorization hash fixtures (no PII)."""
from __future__ import annotations
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "examples/windows_companion"))
from media_control_once import COMMAND_KEYS, PROTOCOL, SCOPE, scoped_nonce
from status_once import scoped_nonce as status_scoped_nonce
from file_send_once import scoped_nonce as receive_scoped_nonce
from file_upload_once import scoped_nonce as upload_scoped_nonce

class PcMediaVectorsTests(unittest.TestCase):
    def test_python_and_dart_share_fixed_vectors(self):
        data = json.loads((ROOT / "docs/pc-link-r6b-media-vectors.json").read_text())
        self.assertEqual(PROTOCOL, data["protocol"])
        self.assertEqual(SCOPE, data["scope"])
        self.assertEqual("CHAPPY-PC-MEDIA-CONTROL-V1", data["domain"])
        self.assertEqual(2, len(data["vectors"]))
        for entry in data["vectors"]:
            nonce = entry["raw_nonce_hex"]
            self.assertEqual(set(COMMAND_KEYS), set(entry["commands"]))
            for cmd, wanted in entry["commands"].items():
                self.assertEqual(wanted, scoped_nonce(nonce, cmd))
                self.assertNotEqual(wanted, status_scoped_nonce(nonce))
                self.assertNotEqual(wanted, receive_scoped_nonce(nonce))
                self.assertNotEqual(wanted, upload_scoped_nonce(nonce))
                self.assertNotEqual(wanted, nonce)
            self.assertEqual(len(set(entry["commands"].values())), 4)

    def test_fail_closed_command_and_nonce_types(self):
        raw = "1" * 64
        for item in ("volume_up\n", "shell", "media", "volume_up;cmd", "", None, 0):
            with self.subTest(item=item), self.assertRaises(ValueError):
                scoped_nonce(raw, item)
        for bad in ("A"*64, "1"*63, "0"*66, "", None, 0, True):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                scoped_nonce(bad, "play_pause")

if __name__ == "__main__":
    unittest.main()

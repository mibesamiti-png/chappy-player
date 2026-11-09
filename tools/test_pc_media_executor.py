"""R6B Windows virtual-media-key emission checks with stubbed user32.

NEVER sends a real key to the runner. Checks fixed allowlist and down/up pair.
"""
from __future__ import annotations
import ctypes
from pathlib import Path
import sys
import unittest
from types import SimpleNamespace
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "examples/windows_companion"))
import media_control_once as media

class VirtualMediaKeyTests(unittest.TestCase):
    def test_four_keys_emit_only_one_matching_down_up_pair(self):
        self.assertEqual(media.COMMAND_KEYS, {
            "volume_up": 0xAF, "volume_down": 0xAE,
            "toggle_mute": 0xAD, "play_pause": 0xB3,
        })
        for command, vk in media.COMMAND_KEYS.items():
            with self.subTest(command=command):
                pressed = mock.Mock()
                fake_user32 = SimpleNamespace(keybd_event=pressed)
                # Patch only the imported module's OS reference; avoid changing
                # global os.name/pathlib during CI, even on non-Windows.
                with mock.patch.object(media, "os", SimpleNamespace(name="nt")):
                    with mock.patch.object(
                        ctypes, "windll", SimpleNamespace(user32=fake_user32),
                        create=True,
                    ):
                        media.execute_windows_media_key(command)
                self.assertEqual(pressed.call_args_list, [
                    mock.call(vk, 0, 0, 0),
                    mock.call(vk, 0, 2, 0),
                ])

    def test_unknown_key_never_reaches_platform(self):
        pressed = mock.Mock()
        with mock.patch.object(media, "os", SimpleNamespace(name="nt")):
            with mock.patch.object(
                ctypes, "windll",
                SimpleNamespace(user32=SimpleNamespace(keybd_event=pressed)),
                create=True,
            ):
                for command in ("", "cmd", "0xFF", "volume_up;cmd", 0, None):
                    with self.subTest(command=command), self.assertRaises(ValueError):
                        media.execute_windows_media_key(command)
        pressed.assert_not_called()

    def test_non_windows_sends_no_keys(self):
        with mock.patch.object(media, "os", SimpleNamespace(name="posix")):
            with self.assertRaises(OSError):
                media.execute_windows_media_key("play_pause")

if __name__ == "__main__":
    unittest.main()

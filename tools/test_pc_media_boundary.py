"""R6A: static guard for action-bound media control without mini-app JS access."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]

class MediaBoundaryTest(unittest.TestCase):
    def test_only_host_paths_expose_media_control(self):
        py = (ROOT / "examples/windows_companion/media_control_once.py").read_text()
        dart = (ROOT / "lib/core/pc_media_once.dart").read_text()
        server = (ROOT / "examples/windows_companion/pairing_server.py").read_text()
        exchange = (ROOT / "lib/core/companion_identity_exchange.dart").read_text()
        cli = (ROOT / "examples/windows_companion/companion.py").read_text()
        page = (ROOT / "lib/screens/companion_pairing_page.dart").read_text()
        for content in (py, dart):
            self.assertIn("CHAPPY-PC-MEDIA-CONTROL-V1", content)
            self.assertIn("volume_up", content)
            self.assertIn("play_pause", content)
        self.assertIn("approve_pc_media=_ask_pc_media_user", server)
        self.assertIn("media_once", server)
        self.assertIn("approvePhoneMedia", exchange)
        self.assertIn("--media-once", cli)
        self.assertIn("pair_media_", page)
        self.assertNotIn("subprocess.", py)
        self.assertNotIn("eval(", py)
        for path in ("lib/core/local_app_server.dart", "lib/screens/app_runner_page.dart"):
            source = (ROOT / path).read_text()
            self.assertNotIn("pc.media.control", source)
            self.assertNotIn("executePcMediaOnce", source)

    def test_no_automatic_preview_start(self):
        cmd = (ROOT / "examples/windows_companion/Start-ChappyMediaOnceV3.cmd").read_text()
        self.assertIn("--start --pair --qr --identity-pair --media-once", cmd)
        self.assertIn("--doctor", cmd)
        self.assertIn("pause", cmd)

if __name__ == "__main__":
    unittest.main()

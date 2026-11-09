"""R5B upload is host-only and no file/write powers reach mini-app JavaScript."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]

class UploadBoundary(unittest.TestCase):
    def test_host_scope_and_pc_owner_destination(self):
        cli = (ROOT / "examples/windows_companion/companion.py").read_text(encoding="utf-8")
        server = (ROOT / "examples/windows_companion/pairing_server.py").read_text(encoding="utf-8")
        store = (ROOT / "examples/windows_companion/file_upload_once.py").read_text(encoding="utf-8")
        ui = (ROOT / "lib/screens/companion_pairing_page.dart").read_text(encoding="utf-8")
        model = (ROOT / "lib/core/companion_identity_exchange.dart").read_text(encoding="utf-8")
        self.assertIn("--receive-file-once", cli)
        self.assertIn("SelectedDestination(input(", server)
        self.assertIn("_ask_pc_upload_user", server)
        self.assertIn("RECEIVE", server)
        self.assertIn("os.link(temporary, self.path)", store)
        self.assertNotIn("os.replace(", store)
        self.assertNotIn("subprocess", store)
        self.assertIn("pcUploadScopedNonce", model)
        self.assertIn("pair_upload_once", ui)
        self.assertIn("approvePhoneUpload", ui)
        self.assertIn("uploadOnce", (ROOT / "lib/core/companion_qr_invitation.dart").read_text(encoding="utf-8"))
        for path in (ROOT / "lib").rglob("*.dart"):
            if path.name in ("companion_identity_exchange.dart", "pc_file_upload.dart", "companion_pairing_page.dart"):
                continue
            if "miniapp" in path.name.lower() or "webview" in path.name.lower():
                source = path.read_text(encoding="utf-8")
                self.assertNotIn("pc_file_upload", source)
                self.assertNotIn("uploadPcFileOnce", source)
        lab = (ROOT / "sample_apps/pc_transfer_lab/index.html").read_text(encoding="utf-8")
        self.assertIn("手動QA", lab)
        self.assertIn("RECEIVE", lab)
        self.assertNotIn("fetch(", lab)
        self.assertNotIn("XMLHttpRequest", lab)

    def test_manual_launcher_no_background_persistence(self):
        launch = (ROOT / "examples/windows_companion/Start-ChappyUploadOnceV3.cmd").read_text(encoding="utf-8")
        self.assertIn("--start --pair --qr --identity-pair --receive-file-once", launch)
        self.assertIn("--doctor", launch)
        self.assertIn("pause", launch.lower())
        self.assertNotIn("schtasks", launch.lower())

if __name__ == "__main__":
    unittest.main()

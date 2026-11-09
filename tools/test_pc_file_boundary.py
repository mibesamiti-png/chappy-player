"""Guard R5A PC file transport from remote path and mini-app JS exposure."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class PcFileBoundaryTests(unittest.TestCase):
    def test_windows_only_explicit_file_choice_before_bind(self):
        file = (ROOT / "examples/windows_companion/file_send_once.py").read_text(encoding="utf-8")
        server = (ROOT / "examples/windows_companion/pairing_server.py").read_text(encoding="utf-8")
        cli = (ROOT / "examples/windows_companion/companion.py").read_text(encoding="utf-8")
        self.assertIn("--send-file-once", cli)
        self.assertIn("SelectedFile.from_local_selection(selected_path)", server)
        self.assertLess(server.index("SelectedFile.from_local_selection(selected_path)"),
                        server.index("with BoundedHttpsServer("))
        self.assertIn('answer.get(timeout=MAX_APPROVAL_SECONDS) == "SEND"', server)
        for secret_api in ("subprocess.run", "os.system", "os.walk", "glob(", "os.listdir("):
            self.assertNotIn(secret_api, file)
        self.assertNotIn('data["path"]', server)
        self.assertNotIn('data["filename"]', server)
        self.assertIn("MAX_FILE_BYTES = 4 * 1024 * 1024", file)
        self.assertIn("CHUNK_BYTES = 16 * 1024", file)
        self.assertIn("scoped_nonce", file)

    def test_android_host_only_not_js(self):
        client = (ROOT / "lib/core/companion_identity_exchange.dart").read_text(encoding="utf-8")
        ui = (ROOT / "lib/screens/companion_pairing_page.dart").read_text(encoding="utf-8")
        self.assertIn("pcFileScopedNonce", client)
        self.assertIn("verifyPcReceivedFile", client)
        self.assertIn("FilePicker.platform.saveFile", ui)
        self.assertIn("pair_file_once", ui)
        for path in (ROOT / "lib").rglob("*.dart"):
            if "miniapp" in path.name.lower() or "webview" in path.name.lower():
                source = path.read_text(encoding="utf-8")
                self.assertNotIn("pc_file_receive", source)
                self.assertNotIn("receivePcFileOnce", source)

    def test_lab_no_network_or_new_permission(self):
        html = (ROOT / "sample_apps/pc_transfer_lab/index.html").read_text(encoding="utf-8")
        manifest = ROOT / "sample_apps/pc_transfer_lab/manifest.json"
        self.assertFalse(manifest.exists(), "Packer generates the manifest")
        self.assertIn("PC Transfer Lab", html)
        for forbidden in ("fetch(", "XMLHttpRequest", "WebSocket(", "pc.file.receive", "Chappy.files"):
            self.assertNotIn(forbidden, html)
        guide = (ROOT / "sample_apps/pc_transfer_lab/README.md").read_text(encoding="utf-8")
        self.assertIn("permissions: []", guide)
        self.assertIn("--id local.chappy.pc_transfer_lab", guide)


if __name__ == "__main__":
    unittest.main()

"""Keep R4C PC status on the trusted host only; never give JS free LAN access."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class StatusBoundaryTest(unittest.TestCase):
    def test_explicit_opt_in_and_no_generic_pc_command_or_js_access(self):
        cli = (ROOT / "examples/windows_companion/companion.py").read_text(encoding="utf-8")
        server = (ROOT / "examples/windows_companion/pairing_server.py").read_text(encoding="utf-8")
        result = (ROOT / "examples/windows_companion/pc_status_metrics.py").read_text(encoding="utf-8")
        ui = (ROOT / "lib/screens/companion_pairing_page.dart").read_text(encoding="utf-8")
        self.assertIn("--status-once", cli)
        self.assertIn("args.status_once", cli)
        self.assertIn("status_once=status_once", server)
        self.assertIn("_ask_pc_status_user", server)
        self.assertIn('answer.get(timeout=MAX_APPROVAL_SECONDS) == "STATUS"', server)
        self.assertIn("pcStatusScopedNonce", (ROOT / "lib/core/companion_identity_exchange.dart").read_text(encoding="utf-8"))
        self.assertIn("approvePhoneStatus", ui)
        self.assertIn("pair_status_once", ui)
        for field in ("logical_cpus", "memory_total_bytes", "uptime_seconds"):
            self.assertIn(field, result)
        for item in ("subprocess", "os.system", "socket", "netstat", "gethostname"):
            self.assertNotIn(item, result)
        for path in (ROOT / "lib").rglob("*.dart"):
            if path.name in ("companion_identity_exchange.dart", "pc_status_once.dart") or path.name == "companion_pairing_page.dart":
                continue
            if "miniapp" in path.name.lower() or "webview" in path.name.lower():
                self.assertNotIn("pc_status_once", path.read_text(encoding="utf-8"))
                self.assertNotIn("readStatusOnce", path.read_text(encoding="utf-8"))

    def test_windows_opt_in_starter_not_hidden_or_background(self):
        path = ROOT / "examples/windows_companion/Start-ChappyStatusOnceV3.cmd"
        src = path.read_text(encoding="utf-8")
        self.assertIn("--start --pair --qr --identity-pair --status-once", src)
        self.assertIn("--doctor", src)
        self.assertNotIn("schtasks", src.lower())
        self.assertNotIn("sc create", src.lower())
        self.assertIn("pause", src.lower())


if __name__ == "__main__":
    unittest.main()

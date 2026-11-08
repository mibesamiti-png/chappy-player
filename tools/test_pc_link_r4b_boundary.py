"""R4B: prevent offline fixture/capability model from escaping to mini-apps."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BoundaryChecks(unittest.TestCase):
    def test_debug_only_python_fixture_never_ships_in_windows_exe(self):
        workflow = (ROOT / ".github/workflows/build-windows-companion.yml").read_text(encoding='utf-8')
        app = (ROOT / "examples/windows_companion/companion.py").read_text(encoding='utf-8')
        # A paths-filter entry is safe; only EXE inclusion or execution is forbidden.
        self.assertNotIn("dist/pc_link_r4b_loopback_fixture.py", workflow)
        self.assertNotIn("python tools/pc_link_r4b_loopback_fixture.py", workflow)
        self.assertNotIn("offline_session_preview", app)
        self.assertNotIn("--start --session", app)
        self.assertIn("127.0.0.1", (ROOT / "tools/pc_link_r4b_loopback_fixture.py").read_text(encoding='utf-8'))

    def test_host_only_preview_never_exposed_to_untrusted_js(self):
        core = (ROOT / "lib/core/pc_link_preview_session.dart").read_text(encoding='utf-8')
        allowed = (ROOT / "test/pc_link_preview_session_test.dart").read_text(encoding='utf-8')
        for name in ("miniapp_bridge", "miniapp_server", "miniapp_game_network"):
            source = (ROOT / ("lib/core/" + name + ".dart"))
            if source.exists():
                self.assertNotIn("pc_link_preview_session", source.read_text(encoding='utf-8'))
        for path in (ROOT / "lib").rglob("*.dart"):
            if path.name == "pc_link_preview_session.dart":
                continue
            self.assertNotIn("pc_link_preview_session", path.read_text(encoding='utf-8'),
                             "Preview imported in production Dart code: " + str(path))
        self.assertIn("pc_link_preview_session", allowed)
        self.assertIn("pc.status.read", core)
        self.assertNotIn("process.run", core.lower())
        self.assertNotIn("Socket.connect", core)

    def test_fixed_protocol_does_not_accept_unsafe_scope(self):
        import json
        contract = json.loads(
            (ROOT / "docs/pc-link-session-preview-v1.json").read_text(encoding='utf-8'))
        self.assertEqual(contract["scope"], "OFFLINE_CONTRACT_ONLY")
        self.assertEqual(contract["capability"], "pc.status.read")
        request = contract["request"]
        self.assertEqual(request["kind"], "status-request")
        self.assertNotIn("token", request)
        self.assertNotIn("password", request)
        self.assertNotIn("command", request)
        for forbidden in ("exec", "shell", "fs.read", "files.list", "pc.control"):
            self.assertNotIn(forbidden, contract["capability"])


if __name__ == "__main__":
    unittest.main()

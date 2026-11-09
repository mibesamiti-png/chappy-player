"""NETLAB-05B: BUFFALO owner-pasted client inventory isolation.
This source-level test never accesses a network, router or a user's data.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BuffaloInventoryBoundaryTest(unittest.TestCase):
    def test_owner_only_offline_inventory_and_unknown_device_gate(self):
        parser = (ROOT / "lib/core/buffalo_client_inventory.dart").read_text()
        page = (ROOT / "lib/screens/buffalo_inventory_page.dart").read_text()
        lab = (ROOT / "lib/screens/network_lab_page.dart").read_text()
        docs = (ROOT / "docs/netlab-05b-buffalo-inventory.md").read_text()

        for text in (
            "maxInputLength = 32768", "maxLines = 256",
            "maxDevices = 128", "RegExp", "InternetAddress.tryParse",
            "List.unmodifiable", "normalizeMac",
        ):
            self.assertIn(text, parser)
        for text in (
            "WidgetsBindingObserver", "didChangeAppLifecycleState",
            "CheckboxListTile", "_knownMacs", "_source.clear()",
            "未登録・要確認", "端末側のアプリ登録やペアリングは不要",
        ):
            self.assertIn(text, page)
        self.assertIn("netlab_buffalo_inventory", lab)
        self.assertIn("BuffaloInventoryPage()", lab)
        self.assertIn("manual-import", docs)
        self.assertIn("not automatic", docs.lower())

        for operation in (
            "HttpClient", "HttpServer", "Socket.connect",
            "RawDatagramSocket", "Process.run", "MethodChannel",
            "File.write", "SharedPreferences", "http://",
            "dart:io" + "';" if False else "dart:html",
        ):
            self.assertNotIn(operation, page)
        for operation in (
            "HttpClient", "Socket.connect", "Process.run",
            "File.write", "MethodChannel", "http://",
        ):
            self.assertNotIn(operation, parser)
        # Parsing MAC/IP does not grant mini-app runtime privileges.
        main_activity = (ROOT / "tools/android/MainActivity.kt").read_text()
        self.assertNotIn("BuffaloInventory", main_activity)
        self.assertNotIn("getConntrackList", main_activity)


if __name__ == "__main__":
    unittest.main()

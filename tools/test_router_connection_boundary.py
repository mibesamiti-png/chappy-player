"""NETLAB-05 router API boundary source regression.
No real router traffic, passwords, or physical devices are touched.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RouterLabBoundaryTest(unittest.TestCase):
    def test_host_only_read_only_explicit_access(self):
        reader = (ROOT / "lib/core/openwrt_router_client.dart").read_text()
        page = (ROOT / "lib/screens/router_connection_lab_page.dart").read_text()
        model = (ROOT / "lib/core/router_connection_snapshot.dart").read_text()
        network = (ROOT / "lib/screens/network_lab_page.dart").read_text()

        for name in ("getDHCPLeases", "getConntrackList", "session.login"):
            # session.login is a description; the actual call uses session/login
            self.assertTrue(name in reader or name.replace(".", "', method: '") in reader)
        for term in ("SecurityContext(withTrustedRoots: false)",
                     "badCertificateCallback",
                     "response.certificate", "sha256.convert",
                     "followRedirects = false", "findProxy",
                     "RouterConntrackContract.maxReplyBytes",
                     "approvedWifi", "client.close(force: true)"):
            self.assertIn(term, reader)
        for operation in ("object == 'uci'", "file.exec", "network.wireless", "system.reboot",
                          "ssh", "http://", "ftp://"):
            self.assertNotIn(operation, reader)
        self.assertIn("CheckboxListTile", page)
        self.assertIn("RouterConnectionSnapshot?", page)
        self.assertIn("didChangeAppLifecycleState", page)
        self.assertIn("ModalRoute.of(context)?.isCurrent", page)
        self.assertIn("trafficPairingAllowed", page)
        self.assertIn("_password.clear()", page)
        self.assertIn("item['src'] != deviceIp", model)
        self.assertIn("maxRows = 1200", model)
        self.assertIn("maxVisible = 120", model)
        self.assertIn("netlab_router_connections", network)
        # No new privilege leaks into mini-app JavaScript packages or bridge.
        bridge = (ROOT / "tools/android/MainActivity.kt").read_text()
        self.assertNotIn("openWrt", bridge)
        self.assertNotIn("getConntrackList", bridge)

    def test_router_docs_require_device_owner_and_restrict_release(self):
        docs = (ROOT / "docs/netlab-05-router-connection-lab.md").read_text()
        for key in ("OpenWrt-only", "HTTPS", "physical", "not run", 
                    "Game R8", "no domain-to-IP"):
            self.assertIn(key.lower(), docs.lower())


if __name__ == "__main__":
    unittest.main()

"""Network R7 host-only browser/diagnostic guards before expensive CI setup."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class NetworkR7Boundary(unittest.TestCase):
    def test_host_ui_does_not_grant_miniapp_bridge(self):
        browser = (ROOT / "lib/screens/browser_page.dart").read_text()
        policy = (ROOT / "lib/core/browser_url_policy.dart").read_text()
        diagnostics = (ROOT / "lib/core/network_diagnostic_service.dart").read_text()
        screen = (ROOT / "lib/screens/network_diagnostic_page.dart").read_text()
        lab = (ROOT / "lib/screens/network_lab_page.dart").read_text()
        miniapp = (ROOT / "lib/core/local_app_server.dart").read_text()
        runner = (ROOT / "lib/screens/app_runner_page.dart").read_text()
        for required in ("JavaScriptMode.disabled", "onPermissionRequest:",
                         "request.deny()", "onNavigationRequest:",
                         "BrowserUrlPolicy.allowsNavigation", "WebViewCookieManager()",
                         "clearCache()", "clearLocalStorage()", "_closeSession"):
            self.assertIn(required, browser)
        for required in ("uri.scheme != 'https'", "uri.userInfo.isNotEmpty",
                         "uri.port != 443", "localhost", ".local",
                         "RegExp", "fromNavigation"):
            self.assertIn(required, policy)
        for required in ("InternetAddress.lookup('example.com')",
                         "Uri.parse('https://example.com/')", "client.headUrl",
                         "request.followRedirects = false", "cancel()"):
            self.assertIn(required, diagnostics)
        self.assertIn("showDialog<bool>", screen)
        self.assertIn("NetworkDiagnosticService()", screen)
        self.assertIn("NetworkDiagnosticPage()", lab)
        self.assertIn("BrowserPage()", lab)
        self.assertNotIn("addJavaScriptChannel(", browser)
        self.assertNotIn("MethodChannel(", browser)
        self.assertNotIn("ChappyHost.postMessage", browser)
        self.assertNotIn("NetworkDiagnosticService", miniapp)
        self.assertNotIn("BrowserPage", miniapp)
        self.assertNotIn("NetworkDiagnosticService", runner)
        self.assertNotIn("BrowserUrlPolicy", runner)
        self.assertNotIn("network.diagnostic", miniapp)
        for forbidden in ("Process.run(", "InternetAddress.lookup(",
                          "Socket.connect(", "RawDatagramSocket"):
            self.assertNotIn(forbidden, browser)

    def test_private_lab_is_not_auto_published(self):
        app = ROOT / "sample_apps/browser_lab"
        self.assertFalse((app / "manifest.json").exists())
        catalog = (ROOT / "tools/build_chappy_catalog.py").read_text()
        self.assertNotIn("local.chappy.browser_lab", catalog)

if __name__ == "__main__":
    unittest.main()

"""Network R7: private Browser Lab static and ZIP zero-permission guard."""
from pathlib import Path
import json
import tempfile
import unittest
import zipfile
from html.parser import HTMLParser
from pack_html_chappy import package_html

ROOT = Path(__file__).resolve().parents[1]

class Tags(HTMLParser):
    def __init__(self):
        super().__init__()
        self.checks = []
        self.unwanted = []
        self.scripts = 0

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "input" and "data-r7" in attrs:
            self.checks.append(attrs["data-r7"])
            if attrs.get("type") != "checkbox":
                self.unwanted.append("non-checkbox")
        if tag in ("iframe", "form", "link") or (
                tag == "script" and attrs.get("src")):
            self.unwanted.append(tag)
        if tag == "script":
            self.scripts += 1

class R7BrowserLabTests(unittest.TestCase):
    def test_offline_only_not_a_browser_or_lan_bridge(self):
        directory = ROOT / "sample_apps/browser_lab"
        self.assertFalse((directory / "manifest.json").exists())
        html = (directory / "index.html").read_text(encoding="utf-8")
        tags = Tags()
        tags.feed(html)
        self.assertEqual(len(tags.checks), 12)
        self.assertEqual(len(set(tags.checks)), 12)
        self.assertEqual(tags.unwanted, [])
        self.assertEqual(tags.scripts, 1)
        for token in ("fetch(", "WebSocket(", "XMLHttpRequest", "navigator.mediaDevices",
                      "window.Chappy", "Chappy.", "localStorage", "sessionStorage",
                      "indexedDB", "window.open(", "eval(", "new Function("):
            self.assertNotIn(token, html)
        self.assertIn('id="output" readonly', html)

    def test_package_permissions_are_empty(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "browser-lab.chappy"
            package_html(ROOT / "sample_apps/browser_lab", path,
                         "local.chappy.browser_lab", "Browser Lab", "0.1.0")
            with zipfile.ZipFile(path) as archive:
                manifest = json.loads(archive.read("manifest.json"))
                self.assertEqual(manifest["id"], "local.chappy.browser_lab")
                self.assertEqual(manifest["permissions"], [])
                self.assertIn("index.html", archive.namelist())

if __name__ == "__main__":
    unittest.main()

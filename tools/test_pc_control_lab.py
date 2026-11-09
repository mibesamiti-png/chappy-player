"""Ensure private R6B PC Control Lab is genuinely offline and unprivileged."""
from __future__ import annotations
from html.parser import HTMLParser
from pathlib import Path
import json
import tempfile
import unittest
import zipfile
from pack_html_chappy import package_html

ROOT = Path(__file__).resolve().parents[1]

class HtmlTags(HTMLParser):
    def __init__(self):
        super().__init__()
        self.checks = []
        self.external = []
        self.script_count = 0
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "input" and "data-r6b" in attrs:
            self.checks.append(attrs["data-r6b"])
            if attrs.get("type") != "checkbox":
                self.external.append("non-checkbox")
        if tag in ("form", "iframe", "link") or (
                tag == "script" and "src" in attrs):
            self.external.append(tag)
        if tag == "script":
            self.script_count += 1

class PcControlLabTests(unittest.TestCase):
    def test_source_has_only_manual_qa(self):
        source = ROOT / "sample_apps/pc_control_lab"
        self.assertFalse((source / "manifest.json").exists())
        html = (source / "index.html").read_text(encoding="utf-8")
        tags = HtmlTags()
        tags.feed(html)
        self.assertEqual(len(tags.checks), 13)
        self.assertEqual(len(set(tags.checks)), 13)
        self.assertEqual(tags.external, [])
        self.assertEqual(tags.script_count, 1)
        for forbidden in ("fetch(", "WebSocket(", "XMLHttpRequest",
                          "localStorage", "sessionStorage", "indexedDB",
                          "Chappy.", "navigator.mediaDevices",
                          "window.open(", "pc.media.control", "eval("):
            self.assertNotIn(forbidden, html)
        self.assertIn("Start-ChappyMediaOnceV3.cmd", html)
        self.assertIn('id="output" readonly', html)

    def test_packer_yields_empty_permissions_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "pc-control-lab.chappy"
            package_html(ROOT / "sample_apps/pc_control_lab", dest,
                         "local.chappy.pc_control_lab", "PC Control Lab", "0.1.0")
            with zipfile.ZipFile(dest) as archive:
                manifest = json.loads(archive.read("manifest.json"))
                self.assertEqual(manifest["id"], "local.chappy.pc_control_lab")
                self.assertEqual(manifest["version"], "0.1.0")
                self.assertEqual(manifest["permissions"], [])
                self.assertIn("index.html", archive.namelist())
                self.assertIn(b"data-r6b", archive.read("index.html"))

if __name__ == "__main__":
    unittest.main()

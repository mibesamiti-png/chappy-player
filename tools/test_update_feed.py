"""Smoke-test the offline public update-feed generator (no real signing key)."""
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).with_name("generate_update_feed.py").resolve()

with tempfile.TemporaryDirectory(prefix="chappy_feed_test_") as dirname:
    root = Path(dirname)
    apk = root / "sample.apk"
    fake = bytes(range(256)) * 10
    apk.write_bytes(fake)
    out = root / "feed.json"
    command = [
        sys.executable, str(SCRIPT),
        "--version", "0.2.0", "--build-number", "42",
        "--apk", "arm64-v8a", str(apk), "https://example.org/chappy.apk",
        "--output", str(out),
        "--release-notes", "Japanese memo bug fixed",
    ]
    good = subprocess.run(command, capture_output=True, text=True)
    assert good.returncode == 0, good.stderr
    feed = json.loads(out.read_text(encoding="utf-8"))
    assert feed["packageId"] == "dev.chappy.chappy_player"
    assert feed["buildNumber"] == 42
    assert feed["artifacts"][0]["sha256"] == hashlib.sha256(fake).hexdigest()
    assert feed["artifacts"][0]["sizeBytes"] == len(fake)

    unsafe = command.copy()
    unsafe[unsafe.index("https://example.org/chappy.apk")] = "http://example.org/insecure.apk"
    denied = subprocess.run(unsafe, capture_output=True, text=True)
    assert denied.returncode != 0, "Plain HTTP feed asset was accepted"
    print("Update feed generator smoke tests passed")

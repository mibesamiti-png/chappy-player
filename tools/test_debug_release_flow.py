"""Offline checks for separate Debug APK update feed and publishing contracts."""
import hashlib
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_debug_feed import generate
from publish_debug_feed import check_feed

TAG = "debug-v0.2.5-b100121"
URL = ("https://github.com/mibesamiti-png/chappy-player-updates/"
       f"releases/download/{TAG}/ChappyPlayerDebug.apk")
with tempfile.TemporaryDirectory(prefix="chappy_debug_feed_") as tmp:
    apk = Path(tmp) / "ChappyPlayerDebug.apk"
    payload = b"test-APK-bytes-" * 128
    apk.write_bytes(payload)
    feed = generate(apk, "0.2.5", 100121, URL, "Debug build tests")
    assert feed["packageId"] == "dev.chappy.chappy_player.debug"
    assert feed["artifacts"][0]["sha256"] == hashlib.sha256(payload).hexdigest()
    assert feed["artifacts"][0]["abi"] == "universal"
    check_feed(feed, TAG)

    def rejected(fn):
        try:
            fn()
        except ValueError:
            return
        raise AssertionError("Invalid Debug feed passed verification")

    rejected(lambda: generate(apk, "0.2.5", 1, URL, "Too small build number"))
    rejected(lambda: generate(apk, "0.2.5", 100121,
                              "https://example.com/ChappyPlayerDebug.apk", "Wrong host"))
    rejected(lambda: generate(apk, "latest", 100121, URL, "Bad version"))
    broken = dict(feed)
    broken["packageId"] = "dev.chappy.chappy_player"
    rejected(lambda: check_feed(broken, TAG))
    broken = dict(feed)
    broken["artifacts"] = [dict(feed["artifacts"][0], androidVersionCode=99)]
    rejected(lambda: check_feed(broken, TAG))
    broken = dict(feed)
    broken["artifacts"] = [dict(feed["artifacts"][0],
                               url="https://example.com/malicious.apk")]
    rejected(lambda: check_feed(broken, TAG))
    rejected(lambda: check_feed(feed, "debug-v0.2.5-b100122"))

signer = (Path(__file__).parent / "configure_debug_release_signing.py").read_text()
assert "CHAPPY_DEBUG_KEYSTORE_B64" in signer
assert "CHAPPY_DEBUG_CERT_SHA256" in signer
assert 'applicationIdSuffix = ".debug"' in signer
assert "CHAPPY_KEYSTORE_B64" not in signer
assert "chappyDebugKeystore" in signer
assert "getByName" in signer

workflow = (Path(__file__).parent.parent /
            ".github/workflows/publish-debug-apk.yml").read_text()
assert "workflow_dispatch:" in workflow
assert "pull_request:" not in workflow
assert "refs/heads/main" in workflow
assert "--prerelease" in workflow
assert "tools/verify_debug_release.py" in workflow
assert "tools/publish_debug_feed.py" in workflow
assert "CHAPPY_DEBUG_CERT_SHA256" in workflow
print("Dedicated Debug APK signing/publishing contract tests passed")

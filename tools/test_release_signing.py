"""Offline smoke test of the release-signing configuration helper."""
import base64
import os
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).with_name("configure_release_signing.py").resolve()
GRADLE_SAMPLE = """
plugins {
    id("com.android.application")
}
android {
    namespace = "dev.chappy.chappy_player"
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
"""

with tempfile.TemporaryDirectory(prefix="chappy_signing_test_") as folder:
    root = Path(folder)
    gradle = root / "android" / "app" / "build.gradle.kts"
    gradle.parent.mkdir(parents=True)
    gradle.write_text(GRADLE_SAMPLE, encoding="utf-8")
    env = dict(os.environ)
    env.update({
        "CHAPPY_KEYSTORE_B64": base64.b64encode(b"test-only\x00" * 32).decode(),
        "CHAPPY_STORE_PASSWORD": "example=pass#1",
        "CHAPPY_KEY_PASSWORD": "example:pass!2",
        "CHAPPY_KEY_ALIAS": "chappy",
    })
    completed = subprocess.run(
        [sys.executable, str(SCRIPT)],
        cwd=root,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr
    assert "example=pass" not in completed.stdout
    assert "chappyRelease" in gradle.read_text(encoding="utf-8")
    props = (root / "android" / "key.properties").read_text(encoding="utf-8")
    assert "example\\=pass\\#1" in props
    assert (root / "android" / "app" / "chappy-release.jks").exists()
    print("Release signing configuration smoke test passed")

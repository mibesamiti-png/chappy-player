"""Offline smoke test using a real temporary PKCS12 signing keystore."""
import base64
import hashlib
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

    # Unlike the old fixture, this is a cryptographically real certificate.
    source_keystore = root / "throwaway-test-keystore.p12"
    password = "example=pass#1"
    env = dict(os.environ)
    env["CHAPPY_TEST_KEY_PASS"] = password
    generated = subprocess.run(
        [
            "keytool", "-genkeypair", "-keystore", str(source_keystore),
            "-storetype", "PKCS12", "-keyalg", "RSA", "-keysize", "2048",
            "-validity", "2", "-alias", "chappy",
            "-dname", "CN=SigningSmokeTest",
            "-storepass:env", "CHAPPY_TEST_KEY_PASS",
            "-keypass:env", "CHAPPY_TEST_KEY_PASS",
            "-noprompt",
        ],
        capture_output=True, check=False,
        env=env,
    )
    assert generated.returncode == 0, "Cannot generate temporary signing test keystore"
    cert = subprocess.run(
        [
            "keytool", "-exportcert", "-keystore", str(source_keystore),
            "-alias", "chappy", "-storepass:env", "CHAPPY_TEST_KEY_PASS",
        ],
        capture_output=True, check=False,
        env=env,
    )
    assert cert.returncode == 0 and cert.stdout, "Cannot export temporary test certificate"
    fingerprint = hashlib.sha256(cert.stdout).hexdigest()

    env.update({
        "CHAPPY_KEYSTORE_B64": base64.b64encode(source_keystore.read_bytes()).decode(),
        "CHAPPY_STORE_PASSWORD": password,
        "CHAPPY_KEY_PASSWORD": password,
        "CHAPPY_KEY_ALIAS": "chappy",
        "CHAPPY_RELEASE_CERT_SHA256": fingerprint,
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
    assert password not in completed.stdout
    assert "matches pinned SHA-256" in completed.stdout
    assert "chappyRelease" in gradle.read_text(encoding="utf-8")
    props = (root / "android" / "key.properties").read_text(encoding="utf-8")
    assert "example\\=pass\\#1" in props
    assert (root / "android" / "app" / "chappy-release.jks").read_bytes() == source_keystore.read_bytes()

    # Fingerprint mismatches are rejected before Gradle is configured.
    bad_env = dict(env)
    bad_env["CHAPPY_RELEASE_CERT_SHA256"] = "0" * 64
    failed = subprocess.run(
        [sys.executable, str(SCRIPT)], cwd=root, env=bad_env,
        text=True, capture_output=True, check=False,
    )
    assert failed.returncode != 0
    assert "does not match GitHub Actions variable" in failed.stderr

print("Release signing configuration smoke test passed")

"""Verify actual universal Debug APK ID, pinned certificate and versionCode."""
import os
from pathlib import Path
import re
import subprocess
from verify_signed_release import find_apksigner, parse_apk_certificate_digests

APK = Path("build/app/outputs/flutter-apk/app-debug.apk")
def verify():
    expected_cert = os.environ.get("CHAPPY_DEBUG_CERT_SHA256", "").strip().lower()
    if not re.fullmatch(r"[a-f0-9]{64}", expected_cert):
        raise RuntimeError("Missing dedicated Debug certificate pin")
    expected_code = int(os.environ["CHAPPY_DEBUG_BUILD_NUMBER"])
    expected_name = os.environ["CHAPPY_DEBUG_VERSION"] + "-debug"
    if not APK.is_file() or APK.stat().st_size < 1024:
        raise RuntimeError("Missing Debug APK")
    signer = find_apksigner()
    aapt = signer.with_name("aapt")
    if not aapt.is_file():
        raise RuntimeError("Android aapt not found")
    meta = subprocess.run([str(aapt), "dump", "badging", str(APK)],
                          capture_output=True, text=True)
    if meta.returncode:
        raise RuntimeError("Could not read Debug APK package metadata")
    match = re.search(
        r"package: name='([^']+)' versionCode='(\\d+)' versionName='([^']+)'",
        meta.stdout)
    if match is None or match.group(1) != "dev.chappy.chappy_player.debug" or (
        int(match.group(2)) != expected_code or match.group(3) != expected_name
    ):
        raise RuntimeError("Wrong Debug package ID, versionCode or versionName")
    signature = subprocess.run(
        [str(signer), "verify", "--verbose", "--print-certs", str(APK)],
        capture_output=True, text=True)
    if signature.returncode:
        raise RuntimeError("Android rejected Debug APK signature")
    actual = parse_apk_certificate_digests(signature.stdout)
    if any(d != expected_cert for d in actual):
        raise RuntimeError("Debug APK signer is not the pinned Debug key")
    print("Universal Debug APK package/version/signature verification passed")
if __name__ == "__main__":
    verify()

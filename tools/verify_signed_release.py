"""Fail closed unless every public release APK has the expected stable signer.

Used only by the manually triggered signed publication workflow. It checks the
real APK signer via Android build-tools, not just the existence of a keystore.
"""
import os
from pathlib import Path
import re
import subprocess
import zipfile

ROOT = Path("build/app/outputs/flutter-apk")
EXPECTED = {
    "arm64-v8a": ROOT / "app-arm64-v8a-release.apk",
    "armeabi-v7a": ROOT / "app-armeabi-v7a-release.apk",
    "x86_64": ROOT / "app-x86_64-release.apk",
}


def find_apksigner() -> Path:
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        raise RuntimeError("Android SDK path is not configured")
    candidates = list((Path(sdk) / "build-tools").glob("*/apksigner"))
    if not candidates:
        raise RuntimeError("Android apksigner was not found")
    return sorted(candidates)[-1]


def verify() -> None:
    expected_cert = os.environ.get("CHAPPY_RELEASE_CERT_SHA256", "").strip()
    if not re.fullmatch(r"[a-fA-F0-9]{64}", expected_cert):
        raise RuntimeError(
            "Set CHAPPY_RELEASE_CERT_SHA256 to the 64-char SHA-256 fingerprint "
            "of the one permanent signing certificate before publication")
    expected_cert = expected_cert.lower()
    signer = find_apksigner()

    for abi, filename in EXPECTED.items():
        if not filename.is_file():
            raise RuntimeError(f"Signed {abi} APK not found: {filename}")
        with zipfile.ZipFile(filename) as archive:
            names = set(archive.namelist())
            if "AndroidManifest.xml" not in names or "classes.dex" not in names:
                raise RuntimeError(f"{abi}: essential Android entries missing")
            if f"lib/{abi}/libflutter.so" not in names:
                raise RuntimeError(f"{abi}: expected Flutter native library missing")
            all_abis = {
                name.split("/")[1] for name in names
                if name.startswith("lib/") and name.count("/") > 1
            }
            if all_abis != {abi}:
                raise RuntimeError(f"{abi}: unexpected ABI contents: {all_abis}")
            corrupt = archive.testzip()
            if corrupt:
                raise RuntimeError(f"{abi}: ZIP corruption at {corrupt}")
        response = subprocess.run(
            [str(signer), "verify", "--verbose", "--print-certs", str(filename)],
            capture_output=True, text=True,
        )
        if response.returncode != 0:
            raise RuntimeError(f"{abi}: APK signature verification failed")
        matches = re.findall(
            r"Signer #\d+ certificate SHA-256 digest:\s*([a-fA-F0-9]{64})",
            response.stdout,
        )
        if len(matches) != 1:
            raise RuntimeError(
                f"{abi}: expected exactly one APK signer certificate, "
                f"found {len(matches)}. Publication refused.")
        actual_cert = matches[0].lower()
        if actual_cert != expected_cert:
            raise RuntimeError(
                f"{abi}: APK certificate SHA-256 {actual_cert.upper()} "
                f"does not match pinned SHA-256 {expected_cert.upper()}. "
                "Publication refused. Check release signing configuration.")
        print(f"{abi}: signed APK verified, pinned cert matched, "
              f"{filename.stat().st_size} bytes")
    print("All release artifacts passed signature and archive checks")


if __name__ == "__main__":
    verify()

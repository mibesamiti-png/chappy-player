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


def parse_apk_certificate_digests(output: str) -> list[str]:
    """Extract SHA-256 certificates from the trusted apksigner verify output.

    Labels vary by Android build-tools version, so only interpret the field
    named 'certificate SHA-256 digest:' rather than assuming signer numbering.
    apksigner must independently verify the APK successfully before this is
    called. All reported certificate hashes must match the pinned certificate.
    """
    marker = "certificate SHA-256 digest:"
    digests = []
    for line in output.splitlines():
        if marker not in line:
            continue
        _, _, value = line.partition(marker)
        # Support plain hexadecimal and colon-separated certificate hashes.
        normalized = "".join(value.split()).replace(":", "")
        if not re.fullmatch(r"[0-9a-fA-F]{64}", normalized):
            raise RuntimeError(
                "apksigner returned an unrecognized certificate SHA-256 field "
                f"(raw length {len(value)}, normalized length {len(normalized)}); "
                "publication refused"
            )
        digests.append(normalized.lower())
    if not digests:
        raise RuntimeError(
            "apksigner did not report a certificate SHA-256 digest; "
            "publication refused"
        )
    return digests

def verify() -> None:
    expected_cert = os.environ.get("CHAPPY_RELEASE_CERT_SHA256", "").strip()
    if not re.fullmatch(r"[a-fA-F0-9]{64}", expected_cert):
        raise RuntimeError(
            "Set CHAPPY_RELEASE_CERT_SHA256 to the 64-char SHA-256 fingerprint "
            "of the one permanent signing certificate before publication")
    expected_cert = expected_cert.lower()
    signer = find_apksigner()
    aapt = signer.with_name("aapt")
    if not aapt.is_file():
        raise RuntimeError("Android aapt tool was not found")
    base_build = int(os.environ["GITHUB_RUN_NUMBER"])
    if base_build < 1 or base_build >= 1000:
        raise RuntimeError("Split ABI build number has exceeded safe range")
    expected_version = os.environ["CHAPPY_VERSION"]
    offsets = {"armeabi-v7a": 1000, "arm64-v8a": 2000, "x86_64": 4000}

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
        metadata = subprocess.run(
            [str(aapt), "dump", "badging", str(filename)],
            capture_output=True, text=True,
        )
        if metadata.returncode != 0:
            raise RuntimeError(f"{abi}: cannot inspect APK versionCode")
        match = re.search(
            r"package: name='([^']+)' versionCode='(\\d+)' versionName='([^']+)'",
            metadata.stdout,
        )
        expected_code = base_build + offsets[abi]
        if (match is None or match.group(1) != "dev.chappy.chappy_player"
                or int(match.group(2)) != expected_code
                or match.group(3) != expected_version):
            raise RuntimeError(
                f"{abi}: actual APK package/versionCode/versionName does not "
                f"match expected {expected_code}/{expected_version}. "
                "Publication refused."
            )
        response = subprocess.run(
            [str(signer), "verify", "--verbose", "--print-certs", str(filename)],
            capture_output=True, text=True,
        )
        if response.returncode != 0:
            raise RuntimeError(f"{abi}: APK signature verification failed")
        digests = parse_apk_certificate_digests(response.stdout)
        for actual_cert in digests:
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

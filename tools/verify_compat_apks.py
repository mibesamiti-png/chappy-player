"""Verify per-ABI APK structure and Android signatures in GitHub Actions.

A green CI build alone does not prove that the APK installs on a particular
Android phone. This adds the checks a package manager expects before users test.
"""
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

OUTPUT = Path("build/app/outputs/flutter-apk")
EXPECTED = {
    "arm64-v8a": "app-arm64-v8a-debug.apk",
    "armeabi-v7a": "app-armeabi-v7a-debug.apk",
    "x86_64": "app-x86_64-debug.apk",
}


def locate_apksigner():
    resolved = shutil.which("apksigner")
    if resolved:
        return resolved
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        raise SystemExit("ANDROID_HOME is missing; cannot verify APK signatures")
    tools = list((Path(sdk) / "build-tools").glob("*/apksigner"))
    if not tools:
        raise SystemExit("Android build-tools/apksigner was not found")
    return str(sorted(tools)[-1])


def verify():
    signer = locate_apksigner()
    lines = [
        "Chappy Player Android installation compatibility report",
        "Build type: debug; the debug signing key can change between CI runs.",
        "Supported ABIs: arm64-v8a, armeabi-v7a, x86_64.",
        "APK installation on actual hardware has NOT been tested.",
        "",
    ]
    for abi, file_name in EXPECTED.items():
        path = OUTPUT / file_name
        if not path.exists():
            raise SystemExit(f"Missing split APK for {abi}: {path}")
        with zipfile.ZipFile(path) as archive:
            names = set(archive.namelist())
            if not {"AndroidManifest.xml", "classes.dex"}.issubset(names):
                raise SystemExit(f"{path}: missing mandatory Android app components")
            if f"lib/{abi}/libflutter.so" not in names:
                raise SystemExit(f"{path}: missing expected Flutter engine for {abi}")
            other = {
                name.split("/")[1]
                for name in names
                if name.startswith("lib/") and name.count("/") > 1
            }
            if other != {abi}:
                raise SystemExit(f"{path}: unexpected ABIs {sorted(other)}")
            broken = archive.testzip()
            if broken is not None:
                raise SystemExit(f"{path}: corrupt ZIP member: {broken}")

        signed = subprocess.run(
            [signer, "verify", "--verbose", str(path)],
            capture_output=True, text=True, check=False,
        )
        if signed.returncode != 0:
            raise SystemExit(
                f"{path}: APK signature failed verification:\n{signed.stderr}"
            )
        size_mib = path.stat().st_size / (1024 * 1024)
        lines.append(f"{abi}: PASS, {size_mib:.1f} MiB, ZIP intact, signature verified")
        print(lines[-1])

    report = OUTPUT / "compatibility-report.txt"
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Report written to {report}")


if __name__ == "__main__":
    verify()

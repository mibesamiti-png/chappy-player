"""Verify that the actual built debug APK embeds all eight sample .chappy assets.

A successful pack step alone is insufficient: Flutter must have included the
files in its asset bundle. This tool never reads or needs release signing keys.
"""
import hashlib
import json
from pathlib import Path
import sys
import zipfile

from prepare_debug_samples import SAMPLES


def verify(apk: Path) -> None:
    if not apk.is_file():
        raise ValueError(f"Debug APK missing: {apk}")
    prefix = "assets/flutter_assets/debug_sample_assets/"
    with zipfile.ZipFile(apk, "r") as android:
        raw = android.read(prefix + "index.json")
        index = json.loads(raw)
        entries = index["entries"]
        if index.get("schemaVersion") != 1 or len(entries) != len(SAMPLES):
            raise ValueError("APK missing full debug sample manifest")
        expected_ids = {entry[0] for entry in SAMPLES}
        actual_ids = {entry["id"] for entry in entries}
        if expected_ids != actual_ids:
            raise ValueError("Actual APK sample IDs do not match the debug catalog")
        for entry in entries:
            name = entry["asset"]
            if not name.startswith("debug_sample_assets/") or ".." in name:
                raise ValueError(f"Unsafe sample asset path: {name}")
            data = android.read("assets/flutter_assets/" + name)
            if (len(data) != entry["sizeBytes"] or
                    hashlib.sha256(data).hexdigest() != entry["sha256"]):
                raise ValueError(f"Embedded debug sample mismatch: {name}")
            import io
            with zipfile.ZipFile(io.BytesIO(data), "r") as mini:
                pkg = json.loads(mini.read("manifest.json"))
                if pkg.get("id") != entry["id"]:
                    raise ValueError("Embedded mini-app manifest ID mismatch")
    print(f"Verified {len(entries)} bundled .chappy mini-apps inside {apk.name}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: verify_debug_sample_apk.py path/to/app-debug.apk")
    verify(Path(sys.argv[1]))

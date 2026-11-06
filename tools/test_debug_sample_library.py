"""Regression tests for debug APK-only mini-app seed assets.

Runs locally via Python stdlib, without Android SDK, modifying only temporary
files. Production pubspec and signed release workflow must remain untouched.
"""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from prepare_debug_samples import build, OUTPUT, SAMPLES, ASSET_MARKER  # noqa: E402


def check():
    assert len(SAMPLES) == 8
    assert len({row[0] for row in SAMPLES}) == 8
    original = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    assert ASSET_MARKER not in original
    release = (ROOT / ".github/workflows/publish-signed-apks.yml").read_text(
        encoding="utf-8"
    )
    assert "prepare_debug_samples.py" not in release
    assert OUTPUT not in release
    gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    assert OUTPUT + "/" in gitignore
    with tempfile.TemporaryDirectory(prefix="chappy_seed_test_") as tmp:
        root = Path(tmp)
        (root / "pubspec.yaml").write_text(original, encoding="utf-8")
        for _, _, _, dirname, _ in SAMPLES:
            shutil.copytree(
                ROOT / "sample_apps" / dirname,
                root / "sample_apps" / dirname,
            )

        first = build(root)
        second = build(root)  # Idempotent; never duplicate pubspec entry.
        assert first == second
        patched = (root / "pubspec.yaml").read_text(encoding="utf-8")
        assert patched.count(ASSET_MARKER) == 1
        assert patched.replace(ASSET_MARKER, "") == original
        assert len(first["entries"]) == 8
        assert first["seedVersion"] == "v1"

        for row, entry in zip(SAMPLES, first["entries"]):
            app_id, name, version, _, permissions = row
            assert entry["id"] == app_id
            file = root / entry["asset"]
            data = file.read_bytes()
            assert len(data) == entry["sizeBytes"]
            assert hashlib.sha256(data).hexdigest() == entry["sha256"]
            assert len(data) <= 12 * 1024 * 1024
            with zipfile.ZipFile(file, "r") as archive:
                names = archive.namelist()
                assert names.count("manifest.json") == 1
                assert names.count("index.html") == 1
                assert len(names) <= 200
                assert len({name.lower() for name in names}) == len(names)
                manifest = json.loads(archive.read("manifest.json"))
                assert manifest["id"] == app_id
                assert manifest["name"] == name
                assert manifest["version"] == version
                assert manifest["permissions"] == list(permissions)

        index = json.loads((root / OUTPUT / "index.json").read_text())
        assert index == first

    assert (ROOT / "pubspec.yaml").read_text(encoding="utf-8") == original
    assert not (ROOT / OUTPUT).exists(), "Tests must not leave untracked bundles"
    print("Debug-only packaging tests passed: eight ZIP packages, checksums, "
          "single pubspec injection and signed-release isolation")


if __name__ == "__main__":
    check()

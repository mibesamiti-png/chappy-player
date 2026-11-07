"""Build eight offline .chappy demos and register assets only in DEBUG builds.

Called by the isolated debug APK GitHub Actions workflow, never by the
signed release pipeline. Creates source-derived archives under the ignored
debug_sample_assets/ directory and adds that directory to the temporary
checkout's pubspec.yaml only. No publishing or remote downloads.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import zipfile

from pack_html_chappy import package_html

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = "debug_sample_assets"
ASSET_MARKER = "    - debug_sample_assets/\n"
PUBSPEC_ANCHOR = "    - sample_memo.chappy\n"
SCHEMA_VERSION = 1
SEED_VERSION = "v1"

# ID, name, version, source, permissions. All are repository-owned examples.
SAMPLES = (
    ("local.chappy.memo", "メモ帳", "0.1.0", "memo", ()),
    ("local.chappy.media_probe", "Chappy Media Lab", "0.1.6",
     "media_probe", ("camera", "microphone")),
    ("local.chappy.recorder", "Chappy Recorder", "0.1.3",
     "video_recorder", ("camera", "microphone")),
    ("local.chappy.device_lab", "Chappy Device Lab", "0.2.0",
     "device_lab", ("motion", "haptics")),
    ("local.chappy.file_lab", "Chappy File Lab", "0.2.2",
     "file_lab", ("files",)),
    ("local.chappy.game_server_lab", "Chappy Game Server Lab", "0.1.1",
     "game_server_lab", ("network", "motion", "haptics")),
    ("local.chappy.touch_lab", "Chappy Touch Lab", "0.1.0",
     "touch_lab", ()),
    ("local.chappy.color_lab", "Chappy Color Lab", "0.1.0",
     "color_lab", ()),
)


def pack_memo(source: Path, destination: Path) -> None:
    """Memo is the only demo with its own source manifest.json."""
    if not (source / "manifest.json").is_file():
        raise ValueError("Memo source manifest not found")
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_STORED) as out:
        for entry in sorted(source.rglob("*")):
            if entry.is_symlink():
                raise ValueError("Symlink in memo demo")
            if entry.is_file():
                rel = entry.relative_to(source).as_posix()
                if not rel.isascii() or ".." in rel.split("/"):
                    raise ValueError("Unsafe memo file name")
                out.write(entry, rel)


def build(root: Path) -> dict:
    root = root.resolve()
    output = root / OUTPUT
    if output.is_symlink():
        raise ValueError("Debug seed directory must not be a symlink")
    output.mkdir(parents=True, exist_ok=True)
    pubspec = root / "pubspec.yaml"
    text = pubspec.read_text(encoding="utf-8")
    if text.count(PUBSPEC_ANCHOR) != 1:
        raise ValueError("Unexpected Flutter assets config")
    if ASSET_MARKER not in text:
        pubspec.write_text(
            text.replace(PUBSPEC_ANCHOR, PUBSPEC_ANCHOR + ASSET_MARKER),
            encoding="utf-8",
        )

    entries = []
    ids = set()
    for app_id, name, version, dirname, perms in SAMPLES:
        if app_id in ids:
            raise ValueError("Duplicate sample ID")
        ids.add(app_id)
        source = root / "sample_apps" / dirname
        target = output / (dirname + ".chappy")
        if target.is_symlink():
            raise ValueError("Unsafe debug package target")
        target.unlink(missing_ok=True)
        if dirname == "memo":
            pack_memo(source, target)
        else:
            package_html(source, target, app_id, name, version, perms)
        data = target.read_bytes()
        if len(data) > 12 * 1024 * 1024:
            raise ValueError("Sample exceeds Chappy package limit")
        with zipfile.ZipFile(target) as archive:
            manifest = json.loads(archive.read("manifest.json"))
            files = archive.namelist()
            if (files.count("manifest.json") != 1 or
                files.count("index.html") != 1 or
                len(files) > 200 or
                manifest.get("id") != app_id or
                manifest.get("name") != name or
                manifest.get("version") != version or
                manifest.get("permissions") != list(perms)):
                raise ValueError("Generated sample manifest mismatch")
        entries.append({
            "id": app_id,
            "asset": OUTPUT + "/" + target.name,
            "sizeBytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        })

    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "seedVersion": SEED_VERSION,
        "entries": entries,
    }
    (output / "index.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Prepared {len(entries)} debug-only samples; no release assets changed")
    return manifest


if __name__ == "__main__":
    build(ROOT)

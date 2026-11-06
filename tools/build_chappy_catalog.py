"""Build a public Chappy Apps catalog from stable/ and debug/ packages.

Example:
  python3 tools/build_chappy_catalog.py --root ./chappy-apps \\
    --output ./chappy-apps/catalog.json

This tool reads files locally and writes JSON only; it never publishes or
uploads to GitHub. All catalog SHA-256 and size fields are measured from bytes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

MAX_PACKAGE = 12 * 1024 * 1024
MAX_CATALOG = 64 * 1024


def build_catalog(root):
    root = Path(root).resolve()
    entries = []
    keys = set()
    for channel in ("stable", "debug"):
        directory = root / channel
        if not directory.exists():
            continue
        if not directory.is_dir() or directory.is_symlink():
            raise ValueError(f"not a safe {channel} directory")
        for path in sorted(directory.glob("*.chappy")):
            if not path.is_file() or path.is_symlink():
                raise ValueError(f"not a regular package: {path}")
            if path.stat().st_size < 100 or path.stat().st_size > MAX_PACKAGE:
                raise ValueError(f"package size out of range: {path.name}")
            if not path.name.isascii() or not re.fullmatch(
                    r"[a-zA-Z0-9][a-zA-Z0-9_.-]*\.chappy", path.name):
                raise ValueError(f"unsafe public package filename: {path.name}")
            with zipfile.ZipFile(path, "r") as archive:
                names = archive.namelist()
                if (names.count("manifest.json") != 1 or
                        names.count("index.html") != 1 or len(names) > 200):
                    raise ValueError(f"invalid .chappy root layout: {path.name}")
                if any(n.startswith("/") or ".." in n.split("/") for n in names):
                    raise ValueError(f"unsafe ZIP path in {path.name}")
                manifest = json.loads(archive.read("manifest.json"))
            if not isinstance(manifest, dict) or manifest.get("formatVersion") != 1:
                raise ValueError(f"invalid .chappy manifest: {path.name}")
            app_id = manifest.get("id")
            name = manifest.get("name")
            version = manifest.get("version")
            if not isinstance(app_id, str) or not re.fullmatch(
                    r"[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)+", app_id):
                raise ValueError(f"invalid app ID: {path.name}")
            if not isinstance(name, str) or not 1 <= len(name.strip()) <= 60:
                raise ValueError(f"invalid app name: {path.name}")
            if not isinstance(version, str) or not re.fullmatch(
                    r"\d{1,9}\.\d{1,9}\.\d{1,9}", version):
                raise ValueError(f"invalid app version: {path.name}")
            permissions = manifest.get("permissions")
            if (manifest.get("entry") != "index.html" or not isinstance(permissions, list) or
                    len(permissions) != len(set(map(str, permissions))) or
                    any(value not in ("camera", "microphone", "motion", "haptics", "files", "network")
                        for value in permissions)):
                raise ValueError(f"unsupported .chappy permissions or entry: {path.name}")
            if (channel, app_id) in keys:
                raise ValueError(f"duplicated app ID in {channel}: {app_id}")
            keys.add((channel, app_id))
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            entries.append({
                "id": app_id,
                "name": name,
                "description": ("開発版：" if channel == "debug" else "安定版：") + name,
                "version": version,
                "channel": channel,
                "url": "https://raw.githubusercontent.com/mibesamiti-png/chappy-apps/"
                       f"main/{channel}/{path.name}",
                "sha256": digest,
                "sizeBytes": path.stat().st_size,
            })
    if len(entries) > 100:
        raise ValueError("too many catalog entries")
    doc = {"schemaVersion": 1, "entries": entries}
    serialized = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
    if len(serialized.encode("utf-8")) > MAX_CATALOG:
        raise ValueError("catalog exceeds 64KiB")
    return serialized


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    content = build_catalog(args.root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(content, encoding="utf-8")
    print(f"Wrote catalog containing {len(json.loads(content)['entries'])} Chappy apps")


if __name__ == "__main__":
    main()

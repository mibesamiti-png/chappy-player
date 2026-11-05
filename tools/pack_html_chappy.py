"""Pack a user-owned offline HTML/JS directory as a .chappy v1 ZIP.

Usage:
  python3 tools/pack_html_chappy.py --source ./asmr-html \\
    --id local.chappy.asmr --name "ASMR Sound Lab" \\
    --version 0.1.0 --output ./asmr-sound-lab.chappy

No source files are uploaded; this is an offline packaging helper.
"""
import argparse
import json
from pathlib import Path
import re
import stat
import zipfile

MAX_ZIP = 12 * 1024 * 1024
MAX_UNPACKED = 24 * 1024 * 1024
MAX_SINGLE = 10 * 1024 * 1024
MAX_FILES = 200


def package_html(source, output, app_id, name, version, permissions=()):
    source, output = Path(source).resolve(), Path(output).resolve()
    if not source.is_dir() or not (source / "index.html").is_file():
        raise ValueError("source must be a directory with index.html")
    if not re.fullmatch(r"[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)+", app_id) or len(app_id) > 100:
        raise ValueError("invalid Chappy app id")
    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 60:
        raise ValueError("invalid Chappy app name")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("version must be X.Y.Z")
    if (source / "manifest.json").exists():
        raise ValueError("remove source manifest.json; the packager creates it")
    if source == output or source in output.parents:
        raise ValueError("output must be outside the source directory")

    permissions = list(permissions)
    if len(permissions) != len(set(permissions)) or any(
            name not in ('camera', 'microphone') for name in permissions):
        raise ValueError('unsupported or duplicate media permission')

    manifest = {
        "formatVersion": 1, "id": app_id, "name": name,
        "version": version, "minPlayerVersion": "0.1.0",
        "entry": "index.html", "permissions": permissions,
    }
    files = []
    unpacked = 0
    for item in sorted(source.rglob("*")):
        parts = item.relative_to(source).parts
        if any(part.startswith(".") for part in parts):
            continue
        if item.is_symlink():
            raise ValueError(f"symbolic links are forbidden: {item}")
        if item.is_dir():
            continue
        if not item.is_file():
            raise ValueError(f"unsupported asset type: {item}")
        relative = item.relative_to(source).as_posix()
        if (not relative.isascii() or len(relative) > 240 or
                "\\" in relative or any(part in ("", ".", "..") for part in parts) or
                relative.lower() in ("manifest.json", "__chappy_boot.js")):
            raise ValueError(f"unsupported Chappy asset path: {relative}")
        if not stat.S_ISREG(item.stat().st_mode):
            raise ValueError(f"not a regular file: {relative}")
        size = item.stat().st_size
        if size > MAX_SINGLE:
            raise ValueError(f"asset is bigger than 10MiB: {relative}")
        unpacked += size
        if unpacked > MAX_UNPACKED:
            raise ValueError("unpacked files exceed 24MiB")
        files.append((relative, item))
    if len(files) + 1 > MAX_FILES:
        raise ValueError("too many files (limit 200)")
    if len({n.lower() for n, _ in files}) != len(files):
        raise ValueError("duplicate case-insensitive asset paths")

    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise ValueError("refusing to overwrite an existing .chappy file")
    try:
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr("manifest.json",
                             json.dumps(manifest, ensure_ascii=False, indent=2))
            for relative, item in files:
                archive.write(item, relative)
        if output.stat().st_size > MAX_ZIP:
            raise ValueError(".chappy package exceeds 12MiB; shrink local assets")
    except Exception:
        output.unlink(missing_ok=True)
        raise
    return output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--id", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--permission", action="append", choices=["camera", "microphone"],
                        default=[], help="Explicit Android media capability")
    args = parser.parse_args()
    output = package_html(args.source, args.output, args.id, args.name, args.version,
                          args.permission)
    print(f"Created {output} ({output.stat().st_size} bytes)")


if __name__ == "__main__":
    main()

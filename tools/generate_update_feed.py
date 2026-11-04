"""Generate a Chappy Player update catalog for an already hosted signed APK.

This creates JSON only. It never uploads APKs or publishes private repository
content. Configure publicly accessible HTTPS downloads and stable signing first.
"""
import argparse
import hashlib
import json
from pathlib import Path
from urllib.parse import urlparse

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", type=int, required=True)
    parser.add_argument("--apk", action="append", nargs=3,
                        metavar=("ABI", "FILE", "HTTPS_URL"), required=True)
    parser.add_argument("--release-notes", default="")
    parser.add_argument("--output", default="chappy-update.json")
    args = parser.parse_args()
    if args.build_number < 1 or args.build_number > 2147483647:
        parser.error("build-number out of range")
    if len(args.release_notes) > 3000:
        parser.error("release notes too long")
    import re
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("expected semantic version, e.g. 0.2.0")
    entries, abis = [], set()
    for abi, filename, url in args.apk:
        if abi not in {"arm64-v8a", "armeabi-v7a", "x86_64", "universal"}:
            parser.error("unsupported ABI")
        if abi in abis:
            parser.error("duplicate ABI")
        abis.add(abi)
        parsed = urlparse(url)
        if (parsed.scheme != "https" or not parsed.netloc or parsed.username
                or parsed.password or parsed.fragment or parsed.port not in (None, 443)):
            parser.error("only ordinary HTTPS URLs are permitted")
        file = Path(filename)
        if not file.is_file():
            parser.error(f"APK does not exist: {file}")
        size = file.stat().st_size
        if size < 1024 or size > 180 * 1024 * 1024:
            parser.error("APK size out of range")
        digest = hashlib.sha256()
        with file.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        entries.append({
            "abi": abi, "url": url, "sha256": digest.hexdigest(),
            "sizeBytes": size,
        })
    result = {
        "schemaVersion": 1,
        "packageId": "dev.chappy.chappy_player",
        "version": args.version,
        "buildNumber": args.build_number,
        "releaseNotes": args.release_notes,
        "artifacts": entries,
    }
    Path(args.output).write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n",
                                  encoding="utf-8")
    print(f"Wrote {args.output} for {len(entries)} signed APK(s)")

if __name__ == "__main__":
    main()

"""Generate a strict, single universal Debug APK public update feed."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import urlparse

PACKAGE = "dev.chappy.chappy_player.debug"
def generate(apk: Path, version: str, build: int, url: str, notes: str) -> dict:
    if not re.fullmatch(r"\\d+\\.\\d+\\.\\d+", version):
        raise ValueError("Invalid Debug version")
    if not 100000 <= build < 2147483647:
        raise ValueError("Invalid high/monotonic Debug versionCode")
    if len(notes) > 3000:
        raise ValueError("Release notes too long")
    tag = f"debug-v{version}-b{build}"
    expected = ("https://github.com/mibesamiti-png/chappy-player-updates/"
                f"releases/download/{tag}/ChappyPlayerDebug.apk")
    if url != expected or urlparse(url).fragment or urlparse(url).query:
        raise ValueError("Wrong Debug release asset URL")
    if not apk.is_file():
        raise ValueError("Debug APK not found")
    size = apk.stat().st_size
    if not 1024 <= size <= 180 * 1024 * 1024:
        raise ValueError("Invalid Debug APK size")
    return {
        "schemaVersion": 1, "packageId": PACKAGE, "version": version,
        "buildNumber": build, "releaseNotes": notes,
        "artifacts": [{
            "abi": "universal", "url": url,
            "sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
            "sizeBytes": size, "androidVersionCode": build,
        }]
    }

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--apk", required=True, type=Path)
    p.add_argument("--version", required=True)
    p.add_argument("--build-number", required=True, type=int)
    p.add_argument("--url", required=True)
    p.add_argument("--release-notes", default="")
    p.add_argument("--output", required=True, type=Path)
    args = p.parse_args()
    feed = generate(args.apk, args.version, args.build_number,
                    args.url, args.release_notes)
    args.output.write_text(
        json.dumps(feed, ensure_ascii=False, indent=2) + "\\n", encoding="utf-8")
    print("Generated verified Debug package feed")
if __name__ == "__main__":
    main()

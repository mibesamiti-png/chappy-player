"""Publish only Debug feed to the public APK dist repo after release upload."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
from urllib.error import HTTPError
from publish_update_catalog import API, github_request

def check_feed(feed: dict, tag: str):
    if feed.get("schemaVersion") != 1 or (
        feed.get("packageId") != "dev.chappy.chappy_player.debug"
    ):
        raise ValueError("Wrong Debug feed schema/package")
    build = feed.get("buildNumber")
    version = feed.get("version")
    if not isinstance(build, int) or not 100000 <= build < 2147483647:
        raise ValueError("Bad Debug build number")
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid Debug version")
    if tag != f"debug-v{version}-b{build}":
        raise ValueError("Debug tag mismatch")
    artifacts = feed.get("artifacts")
    if not isinstance(artifacts, list) or len(artifacts) != 1:
        raise ValueError("Expected exactly one universal Debug APK")
    apk = artifacts[0]
    if not isinstance(apk, dict) or apk.get("abi") != "universal" or (
        apk.get("androidVersionCode") != build
    ):
        raise ValueError("Invalid Debug APK ABI or versionCode")
    expected = (f"https://github.com/mibesamiti-png/chappy-player-updates/"
                f"releases/download/{tag}/ChappyPlayerDebug.apk")
    if apk.get("url") != expected:
        raise ValueError("Invalid Debug asset download URL")
    if not re.fullmatch(r"[a-f0-9]{64}", str(apk.get("sha256", ""))):
        raise ValueError("Invalid Debug APK SHA-256")
    size = apk.get("sizeBytes")
    if not isinstance(size, int) or not 1024 < size < 180 * 1024 * 1024:
        raise ValueError("Invalid Debug APK size")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True, type=Path)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    token = os.environ.get("CHAPPY_PUBLISH_TOKEN", "")
    if not token:
        raise SystemExit("Missing distribution publishing token")
    data = args.file.read_bytes()
    if len(data) >= 64 * 1024:
        raise SystemExit("Debug feed too large")
    feed = json.loads(data)
    check_feed(feed, args.tag)
    repo = github_request(API, token)
    if repo.get("private") is not False or repo.get("default_branch") != "main":
        raise RuntimeError("Invalid public distribution repository")
    url = API + "/contents/debug-update.json"
    previous_sha = None
    try:
        old = github_request(url + "?ref=main", token)
        previous_sha = old["sha"]
        former = json.loads(base64.b64decode(old["content"]))
        if former.get("packageId") != feed["packageId"]:
            raise RuntimeError("Debug feed points to a different package")
        if former.get("buildNumber", 0) >= feed["buildNumber"]:
            raise RuntimeError("Refusing old/same Debug buildNumber")
    except HTTPError as e:
        if e.code != 404:
            raise
    payload = {
        "message": f"Publish Chappy Player Debug {args.tag} metadata",
        "branch": "main",
        "content": base64.b64encode(data).decode("ascii"),
    }
    if previous_sha:
        payload["sha"] = previous_sha
    github_request(url, token, method="PUT", body=payload)
    print("Updated dedicated public Debug APK feed")
if __name__ == "__main__":
    main()

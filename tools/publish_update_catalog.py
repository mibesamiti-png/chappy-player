"""Publish only a signed APK update manifest to the public distro repo.

The source code and signing keystore stay in the private repository. This
action uses an owner-supplied fine-grained token scoped to the public repo.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import re
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

PUBLIC_REPO = "mibesamiti-png/chappy-player-updates"
API = f"https://api.github.com/repos/{PUBLIC_REPO}"
MAX_FEED_BYTES = 64 * 1024


def github_request(url, token, method="GET", body=None):
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "chappy-player-release-workflow",
    }
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = Request(
        url, headers=headers, method=method,
        data=None if body is None else json.dumps(body).encode("utf-8"),
    )
    with urlopen(req, timeout=20) as response:
        return json.loads(response.read(MAX_FEED_BYTES * 4).decode("utf-8"))


def check_feed(feed, tag):
    if not isinstance(feed, dict) or feed.get("schemaVersion") != 1:
        raise ValueError("Invalid schemaVersion")
    if feed.get("packageId") != "dev.chappy.chappy_player":
        raise ValueError("Wrong update packageId")
    if not isinstance(feed.get("buildNumber"), int) or feed["buildNumber"] <= 0:
        raise ValueError("Invalid buildNumber")
    if not re.fullmatch(r"v\d+\.\d+\.\d+-b\d+", tag):
        raise ValueError("Invalid release tag")
    if tag != f"v{feed.get('version')}-b{feed.get('buildNumber')}":
        raise ValueError("Release tag does not match version/build number")
    arts = feed.get("artifacts")
    if not isinstance(arts, list) or len(arts) != 3:
        raise ValueError("Expected three CPU-specific signed APKs")
    expected_abis = {"arm64-v8a", "armeabi-v7a", "x86_64"}
    if {a.get("abi") for a in arts if isinstance(a, dict)} != expected_abis:
        raise ValueError("Wrong or duplicate CPU architectures")
    for art in arts:
        parsed = urlparse(art["url"])
        expected_path = (
            f"/{PUBLIC_REPO}/releases/download/{tag}/"
            f"ChappyPlayer-{art['abi']}.apk"
        )
        if parsed.scheme != "https" or parsed.netloc != "github.com" or (
            parsed.path != expected_path or parsed.query or parsed.fragment
        ):
            raise ValueError("APK URL points outside the official public release")
        if not re.fullmatch(r"[a-f0-9]{64}", art.get("sha256", "")):
            raise ValueError("Invalid APK digest")
        if not isinstance(art.get("sizeBytes"), int) or art["sizeBytes"] <= 1024:
            raise ValueError("Invalid APK size")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", type=Path, required=True)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    token = os.environ.get("CHAPPY_PUBLISH_TOKEN", "").strip()
    if not token:
        raise SystemExit("CHAPPY_PUBLISH_TOKEN not configured")
    data = args.file.read_bytes()
    if len(data) >= MAX_FEED_BYTES:
        raise SystemExit("Update catalog is too large")
    feed = json.loads(data.decode("utf-8"))
    check_feed(feed, args.tag)

    repo = github_request(API, token)
    if repo.get("private") is not False or repo.get("default_branch") != "main":
        raise RuntimeError("Distribution repo must be public with a main branch")

    target = f"{API}/contents/update.json"
    previous_sha = None
    try:
        previous = github_request(target + "?ref=main", token)
        previous_sha = previous["sha"]
        previous_feed = json.loads(base64.b64decode(
            previous["content"]).decode("utf-8"))
        if previous_feed.get("packageId") != feed["packageId"]:
            raise RuntimeError("Existing update feed points to another app")
        if previous_feed.get("buildNumber", 0) >= feed["buildNumber"]:
            raise RuntimeError(
                "Refusing to publish the same or older versionCode")
    except HTTPError as error:
        if error.code != 404:
            raise

    payload = {
        "message": f"Publish Chappy Player {args.tag} APK update metadata",
        "branch": "main",
        "content": base64.b64encode(data).decode("ascii"),
    }
    if previous_sha:
        payload["sha"] = previous_sha

    github_request(target, token, method="PUT", body=payload)
    print("Published update.json to public APK-only repository")
    print(f"Manifest buildNumber: {feed['buildNumber']}; APK count: {len(feed['artifacts'])}")


if __name__ == "__main__":
    main()

"""Offline smoke coverage for publishing only official release metadata."""
import copy
from publish_update_catalog import check_feed

BASE = (
    "https://github.com/mibesamiti-png/chappy-player-updates/"
    "releases/download/v0.2.0-b12/"
)


def example():
    return {
        "schemaVersion": 1,
        "packageId": "dev.chappy.chappy_player",
        "version": "0.2.0",
        "buildNumber": 12,
        "releaseNotes": "バックアップと更新を改善",
        "artifacts": [
            {
                "abi": abi,
                "url": BASE + "ChappyPlayer-" + abi + ".apk",
                "sha256": "a" * 64,
                "sizeBytes": 123456,
            }
            for abi in ("arm64-v8a", "armeabi-v7a", "x86_64")
        ],
    }


def rejects(feed, tag="v0.2.0-b12"):
    try:
        check_feed(feed, tag)
    except ValueError:
        return
    raise AssertionError("Unsafe or invalid update manifest was accepted")


valid = example()
check_feed(valid, "v0.2.0-b12")
rejects(copy.deepcopy(valid), "v0.2.0")
wrong_repo = copy.deepcopy(valid)
wrong_repo["artifacts"][0]["url"] = (
    "https://github.com/attacker/malware/releases/download/v0.2.0-b12/evil.apk"
)
rejects(wrong_repo)
wrong_scheme = copy.deepcopy(valid)
wrong_scheme["artifacts"][0]["url"] = (
    "http://github.com/mibesamiti-png/chappy-player-updates/"
    "releases/download/v0.2.0-b12/ChappyPlayer-arm64-v8a.apk"
)
rejects(wrong_scheme)
duplicate_abis = copy.deepcopy(valid)
duplicate_abis["artifacts"][0]["abi"] = "x86_64"
rejects(duplicate_abis)
not_chappy = copy.deepcopy(valid)
not_chappy["packageId"] = "another.company.app"
rejects(not_chappy)
print("Public APK manifest publisher smoke tests passed")

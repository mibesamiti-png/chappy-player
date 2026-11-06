"""Offline static and format smoke tests for private-video ZIP restore.

The Python format tests intentionally do not claim that Kotlin ran; Android
compilation and device-provider tests are separate gates.
"""
from pathlib import Path
import hashlib
import io
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parent.parent
def read(name): return (ROOT / name).read_text(encoding="utf-8")

native = read("tools/android/NativeVideoZipRestore.kt")
recorder = read("tools/android/NativeVideoRecorder.kt")
host = read("tools/android/MainActivity.kt")
runner = read("lib/screens/app_runner_page.dart")
bridge = read("lib/core/local_app_server.dart")
ui = read("sample_apps/video_recorder/index.html")
patch = read("tools/patch_android.py")

for signature in (
    "Intent.ACTION_OPEN_DOCUMENT", 'type = "application/zip"',
    "ZipInputStream", "Manifest", "manifest.json",
    "MAX_FILES = 100", "MAX_ENTRY_BYTES = 1024L * 1024 * 1024",
    "MAX_TOTAL_BYTES = 4L * 1024 * 1024 * 1024",
    "MAX_MANIFEST_BYTES = 256 * 1024",
    "Video content SHA-256 or size mismatch",
    "staging", "UUID.randomUUID()", "FileOutputStream(dest)",
    "entry.name != \"videos/\" + name",
    "discovered.containsKey(name)", "hashFile(existing, video.size)",
    "A different recording already exists with the same name",
    "video.file.renameTo(destination)", "written", "file.delete()",
    "state.unlockRecorder()", "setPositiveButton", "setNegativeButton",
    "ZIP contains excessive or directory entries",
):
    assert signature in native, signature

for marker in (
    "private var restoringVideos = false",
    "fun beginPrivateRestore(appId: String)",
    "fun endPrivateRestore()",
    "state != \"idle\" || recording != null",
    "restoringVideos || state != \"idle\"",
):
    assert marker in recorder, marker

assert '"restorePrivateVideosZip"' in host
assert "nativeVideo.beginPrivateRestore(owner)" in host
assert "nativeVideo.endPrivateRestore()" in host
assert "zipRestore.onResult(requestCode, resultCode, data)" in host
assert "zipRestore.onDestroy()" in host
assert "case 'video.restoreZip':" in runner
assert "canRequestChappyMedia(widget.app.permissions, ['camera'])" in runner
assert "'restorePrivateVideosZip', {'owner': widget.app.id}" in runner
assert "restoreZip: () => call('video.restoreZip', {})" in bridge
assert "method === 'video.restoreZip'" in bridge
assert "NativeVideoZipRestore.kt" in patch
assert 'id="restoreVideos"' in ui and "video.restoreZip()" in ui
assert "ZIP復元完了" in ui and "既存動画は上書きしていません" in ui

assert "ACTION_OPEN_DOCUMENT_TREE" not in native
assert "MANAGE_EXTERNAL_STORAGE" not in native
assert "java.net" not in native
assert "openOutputStream" not in native, "Restore must not write to public storage"
assert "getExternalStorageDirectory" not in native

# A ZIP fixture matching the exact export's manifest schema, plus corrupted
# and malicious files that the Kotlin validator must reject by contract.
owner = "local.chappy.recorder"
video_name = "Chappy_20261107_123456_001.mp4"
content = b"\x00\x00\x00\x18ftypmp42" + b"\x01" * 128
manifest = {
    "schemaVersion": 1, "type": "chappy-private-video-backup",
    "ownerId": owner, "fileCount": 1,
    "files": [{"name": video_name, "sizeBytes": len(content),
               "sha256": hashlib.sha256(content).hexdigest()}]
}
def archive(payload, description):
    handle = io.BytesIO()
    with zipfile.ZipFile(handle, "w", zipfile.ZIP_STORED) as z:
        z.writestr("videos/" + video_name, payload)
        z.writestr("manifest.json", json.dumps(description))
    return handle.getvalue()

def reference_validation(data):
    with zipfile.ZipFile(io.BytesIO(data)) as zipped:
        names = zipped.namelist()
        assert len(names) == len(set(names))
        assert 1 < len(names) <= 101
        assert set(names) == {"manifest.json", "videos/" + video_name}
        m = json.loads(zipped.read("manifest.json"))
        assert m["ownerId"] == owner and m["fileCount"] == 1
        assert m["type"] == "chappy-private-video-backup"
        item = m["files"][0]
        video = zipped.read("videos/" + item["name"])
        assert re.fullmatch(r"Chappy_[0-9_]+\.mp4", item["name"])
        assert item["sizeBytes"] == len(video)
        assert item["sha256"] == hashlib.sha256(video).hexdigest()
        return video

assert reference_validation(archive(content, manifest)) == content
for bad_payload, bad_manifest in [
    (content + b"changed", manifest),
    (content, {**manifest, "ownerId": "local.other.app"}),
    (content, {**manifest, "files": [{**manifest["files"][0], "sha256": "0" * 64}]}),
]:
    rejected = False
    try:
        reference_validation(archive(bad_payload, bad_manifest))
    except (AssertionError, KeyError, ValueError):
        rejected = True
    assert rejected, "Corrupt or cross-owner ZIP accepted"

print("ZIP restore source boundary checks and fixture format tests passed")

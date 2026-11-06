"""ZIP video backup contract tests; Kotlin/Gradle build remains mandatory."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
def source(path):
    return (ROOT / path).read_text(encoding="utf-8")

backup = source("tools/android/NativeVideoZipBackup.kt")
recorder = source("tools/android/NativeVideoRecorder.kt")
activity = source("tools/android/MainActivity.kt")
runner = source("lib/screens/app_runner_page.dart")
bridge = source("lib/core/local_app_server.dart")
app = source("sample_apps/video_recorder/index.html")
patcher = source("tools/patch_android.py")

for value in (
    "Intent.ACTION_CREATE_DOCUMENT", 'type = "application/zip"',
    "setNegativeButton", "setPositiveButton",
    "ZipOutputStream", "Deflater.NO_COMPRESSION",
    'ZipEntry("videos/" + name)', 'ZipEntry("manifest.json")',
    '"schemaVersion"', '"fileCount"', '"sha256"', '"ownerId"',
    "DigestOutputStream", "MessageDigest.getInstance(\"SHA-256\")",
    "activity.contentResolver.openInputStream(uri)",
    "hashBefore.contentEquals(hashAfter.digest())",
    "callback", "4L * 1024 * 1024 * 1024",
    "if (bytes <= 0", "Thread {",
):
    assert value in backup, value

for value in (
    "privateBackupSources(appId: String)", "privateExportSource(appId, candidate.name)",
    "if (names.size > 100)", "VIDEO_BACKUP_TOO_MANY_FILES",
    "VIDEO_BACKUP_EMPTY", "state != \"idle\"",
):
    assert value in recorder, value

assert 'zipBackup = NativeVideoZipBackup(this)' in activity
assert '"backupPrivateVideosZip"' in activity
assert 'nativeVideo.privateBackupSources(owner)' in activity
assert "zipBackup.begin(owner, sources, result)" in activity
assert "zipBackup.onResult(requestCode, resultCode, data)" in activity
assert "zipBackup.onDestroy()" in activity
assert "if (!micActivityVisible)" in activity

assert "_backupPrivateVideosZip()" in runner
assert "canRequestChappyMedia(widget.app.permissions, ['camera'])" in runner
assert "'backupPrivateVideosZip', {'owner': widget.app.id}" in runner
assert "case 'video.backupZip':" in runner
assert "backupZip: () => call('video.backupZip', {})" in bridge
assert "method === 'video.backupZip'" in bridge
assert "NativeVideoZipBackup.kt" in patcher

assert 'id="backupVideos"' in app
assert "video.backupZip()" in app
assert "ZIPバックアップ完了" in app
assert "元の動画は残ります" in app

assert "ACTION_OPEN_DOCUMENT_TREE" not in backup
assert "MANAGE_EXTERNAL_STORAGE" not in backup
assert "java.net" not in backup
assert "file.delete()" not in backup
print("Private video ZIP backup safety, manifest and JS bridge contracts passed")

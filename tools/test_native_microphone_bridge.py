"""Cross-file contracts for the untrusted mini-app/native AudioRecord boundary.

This is a static smoke test, not an Android compile or hardware test.
"""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
def read(path):
    return (root / path).read_text(encoding="utf-8")

android = read("tools/android/MainActivity.kt")
capture = read("tools/android/NativeMicCapture.kt")
dart = read("lib/screens/app_runner_page.dart")
server = read("lib/core/local_app_server.dart")
media = read("sample_apps/media_probe/index.html")

for method in ["startNativeMic", "readNativeMic", "stopNativeMic"]:
    assert f'"{method}"' in android, method
for method in ["microphone.start", "microphone.levels", "microphone.stop"]:
    assert f"'{method}'" in dart, method
    assert f"'{method}'" in server, method

assert "Manifest.permission.RECORD_AUDIO" in android
assert "micActivityVisible" in android
assert "nativeMic.stop()" in android
assert "override fun onPause()" in android
assert "canRequestChappyMedia(widget.app.permissions, ['microphone'])" in dart
assert "showDialog<bool>" in dart
assert "invokeMapMethod<String, dynamic>" in dart
assert "AudioRecord" in capture
assert "AudioRecord.READ_BLOCKING" in capture
assert "AudioRecord.STATE_INITIALIZED" in capture
assert "List(64) { 0.0 }" in capture
assert "session.envelopes = envelope" in capture
assert "framesRead" in capture
assert "stopNativeMic()" in media
assert "Chappy.microphone.levels()" in media

# This diagnostic returns RMS and coarse envelopes only. Never let untrusted
# mini-app code select AudioRecord input source or output an audio file.
assert "createTempFile" not in capture
assert "FileOutputStream" not in capture
assert "Base64" not in capture
assert "FOREGROUND_SERVICE_MICROPHONE" not in android

print("Native microphone bridge static boundary smoke test passed")

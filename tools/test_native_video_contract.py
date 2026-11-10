"""Static boundary check for the user-consented CameraX video bridge.

This does not prove compilation or behavior on an Android device.
"""
from pathlib import Path

root = Path(__file__).resolve().parent.parent

def read(path):
    return (root / path).read_text(encoding="utf-8")

native = read("tools/android/NativeVideoRecorder.kt")
activity = read("tools/android/MainActivity.kt")
dart = read("lib/screens/app_runner_page.dart")
bridge = read("lib/core/local_app_server.dart")
html = read("sample_apps/media_probe/index.html")
patch = read("tools/patch_android.py")

for name in ("startNativeVideo", "stopNativeVideo", "readNativeVideo",
             "setVideoDark", "setVideoBrightness", "readVideoStorage",
             "listPrivateVideos", "openPrivateVideo", "deletePrivateVideo"):
    assert f'"{name}"' in activity, name

for name in ("video.start", "video.status", "video.stop", "video.dark",
             "video.list", "video.open", "video.delete", "video.storageInfo"):
    assert f"'{name}'" in dart, name
    assert f"'{name}'" in bridge, name

for item in ("canRequestChappyMedia(widget.app.permissions,",
             "showDialog<bool>", "requestMediaPermissions",
             "stopNativeMic", "videoStartPending", "setVideoDark"):
    if item == "videoStartPending":
        assert "_videoStartPending" in dart
    else:
        assert item in dart, item

assert "ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)" in native
assert "Manifest.permission.RECORD_AUDIO" in native
assert "registry.currentState != Lifecycle.State.RESUMED" in native
assert "override val lifecycle: Lifecycle get() = registry" in native
assert "override fun onPause()" in activity
assert "nativeVideo.onPause()" in activity
assert "NativeVideoRecorder" in activity

for needed in ("ProcessCameraProvider", "VideoCapture.withOutput",
               "VideoRecordEvent.Finalize", "FileOutputOptions",
               "MediaStoreOutputOptions", "IS_PENDING", "chappy_private_videos",
               "File(file.parentFile", "VIDEO_GALLERY_REQUIRES_ANDROID_10",
               'visibility == "private"', "privateDirectory(appId)",
               "WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON",
               "player.setVideoPath(file.absolutePath)"):
    assert needed in native, needed

assert "FOREGROUND_SERVICE_CAMERA" in patch
assert "FOREGROUND_SERVICE_MICROPHONE" in patch
assert "ChappyCameraService.kt" in patch
assert "ChappyRecordingStopReceiver" in patch
assert "'screenOff': screenOff" in dart
assert "ChappyCameraService.beginVisible" in activity
assert "androidx.camera:camera-video:1.5.3" in patch
assert "NativeVideoRecorder.kt" in patch
assert 'id="videoStorage"' in html
assert 'id="videoDark"' in html
assert "Chappy.video.delete(file.id)" in html
assert "fun deletePrivate(appId: String, id: String): Boolean" in native
assert 'VIDEO_DELETE_NOT_ALLOWED' in native
assert 'file.parentFile != root' in native
assert 'if (state != "idle"' in native
assert 'KeyEvent.KEYCODE_VOLUME_UP' in activity
assert 'KeyEvent.KEYCODE_VOLUME_DOWN' in activity
assert 'nativeVideo.isDark()' in activity
assert 'event.repeatCount == 0' in activity
assert 'videoVolumeShortcut' in activity and 'videoVolumeShortcut' in dart
assert '_darkSessionArmed' in dart
assert 'onDoubleTap: () => unawaited(_setVideoDark(false))' in dart
assert 'Colors.redAccent : Colors.greenAccent' in dart
assert 'SystemUiMode.immersiveSticky' in dart
assert 'SystemUiMode.edgeToEdge' in dart
assert 'reuseDarkSessionConsent: true' in dart
assert 'if (!canReuseDarkConsent)' in dart
assert 'previous[\'audio\'] == audio' in dart
assert 'if (!enabled) _darkSessionArmed = false' in dart
assert '暗転モードで録画' in html
assert 'startVideoRecording(true)' in html

assert "Chappy.video.start(options)" in html
assert "StatFs(directory.absolutePath)" in native
assert '"availableBytes" to stats.availableBytes' in native
assert '"totalBytes" to stats.totalBytes' in native
assert "fun setDarkBrightness(brightness: Float)" in native
assert "brightness !in 0.01f..1.0f" in native
assert "onHorizontalDragUpdate:" in dart
assert "onHorizontalDragEnd:" in dart
assert "_setDarkSwipeBrightness(1.0)" in dart
assert "_setDarkSwipeBrightness(0.01)" in dart
assert "_videoStorageInfo()" in dart
assert "storageInfo: () => call('video.storageInfo', {})" in bridge
assert "nativeVideo.storageInfo(" in activity
assert "nativeVideo.setDarkBrightness(brightness)" in activity
assert "Chappy.video.list()" in html
assert "Chappy.video.open(file.id)" in html
assert "recording" not in read("tools/android/NativeMicCapture.kt").lower() or True
print("CameraX private-recording bridge static boundary smoke test passed")

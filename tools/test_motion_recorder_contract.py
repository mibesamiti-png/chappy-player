"""Source-only CAMREC-13 motion recording contract; not physical CameraX verification."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]

def source(path):
    return (root / path).read_text(encoding="utf-8")

analyzer = source("tools/android/NativeMotionAnalyzer.kt")
recorder = source("tools/android/NativeVideoRecorder.kt")
activity = source("tools/android/MainActivity.kt")
runner = source("lib/screens/app_runner_page.dart")
html = source("sample_apps/video_recorder/index.html")
installer = source("tools/patch_android.py")
qa = source("tools/test_chappy_recorder.js")

for fragment in [
    "ImageAnalysis.Analyzer", "image.planes[0]", "columns = 16",
    "rows = 12", "SystemClock.elapsedRealtime()", "250L",
    "meanNow", "meanOld", "residual", "sensitivity.coerceIn(0, 100)",
    "onSample(changedPercent, moving, true)",
    "onFailure()", "image.close()",
]:
    assert fragment in analyzer, fragment
for forbidden in ("HttpURLConnection", "Socket(", "FileOutputStream", "Base64",
                  "BitmapFactory", "ImageReader.newInstance", "compress("):
    assert forbidden not in analyzer, forbidden
for fragment in [
    "motionMode", "motionIdleSeconds", "motionSensitivity",
    "requestedMotionMode !in listOf", "requestedIdleSeconds !in 10..300",
    "requestedSensitivity !in 0..100", "motionStreak >= 2",
    "motionLastMovementMs", "motionFrames < 3",
    "motionAnalysis", "releaseMotionAnalysis()", "setAnalyzer(",
    "ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST",
    "camera.bindToLifecycle(this, selector, capture, analysis)",
    "recording?.pause()", "recording?.resume()", "motionAutoStopped = true",
    "motionStatus = \"error\"", "onPause()", "stop()",
]:
    assert fragment in recorder, fragment
assert recorder.index("motionStreak >= 2") < recorder.index("recording?.pause()")
assert "if (motionFailed || motionFrames < 3 || motionPaused) return" in recorder
assert "if (state == \"initializing\")" in recorder
assert "motionPaused" in recorder and "motionScore" in recorder
assert "nativeVideo.onPause()" in activity
assert "nativeVideo.start(owner, lens, quality, sound, visibility, result," in activity
for fragment in ("motionMode", "motionIdleSeconds", "motionSensitivity",
                 "sameMotion", "previousMotion", "Invalid motion recording options",
                 "Unsupported motion recording options"):
    assert fragment in runner, fragment
for fragment in ("id=\"motionMode\"", "id=\"motionIdle\"",
                 "id=\"motionSensitivity\"", "id=\"motionFeedback\"",
                 "motionSupported", "mode !== 'normal' && !motionSupported",
                 "motionState === 'paused'", "motionAutoStopped"):
    assert fragment in html, fragment
assert "id=\"recordDark\"" in html and "id=\"recordStop\"" in html
assert "tools/android/NativeMotionAnalyzer.kt" in installer
assert "image.close()" in analyzer and "finally {" in analyzer
assert "asPersistentRecording()" not in recorder
assert "FOREGROUND_SERVICE_CAMERA" not in installer
assert "FOREGROUND_SERVICE_MICROPHONE" not in installer
assert "スマート録画" in html
assert "smart pause/stop options" in qa
print("CAMREC-13 motion recording source boundary checks passed (NOT physical recording).")

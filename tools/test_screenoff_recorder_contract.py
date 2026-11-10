"""Static smoke tests for explicit screen-off camera FGS.

This only checks source contracts. Android compile and a physical lock-screen
recording test are necessary before shipping to production.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def src(path): return (ROOT/path).read_text(encoding="utf-8")

service = src("tools/android/ChappyCameraService.kt")
activity = src("tools/android/MainActivity.kt")
recorder = src("tools/android/NativeVideoRecorder.kt")
runner = src("lib/screens/app_runner_page.dart")
html = src("sample_apps/video_recorder/index.html")
patch = src("tools/patch_android.py")

for text in (
    "ContextCompat.startForegroundService(activity, intent)",
    "fun beginVisible(activity: MainActivity",
    'if (isActive()) throw IllegalStateException("SCREEN_OFF_VIDEO_BUSY")',
    "Manifest.permission.CAMERA",
    "Manifest.permission.RECORD_AUDIO",
    "Manifest.permission.POST_NOTIFICATIONS",
    "ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA",
    "ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE",
    "startForeground(NOTICE_ID, ongoingNotification(), type)",
    "NativeVideoRecorder(this, onFinalized = { finishRecording() })",
    "stopForeground(STOP_FOREGROUND_REMOVE)",
    "ChappyRecordingStopReceiver",
    "PendingIntent.getBroadcast",
    ".setOngoing(true)",
    "override fun onStartCommand",
    "return START_NOT_STICKY",
    "private fun stopRecording()",
    "override fun onDestroy()",
):
    assert text in service, text
assert "onReceive(context: Context, intent: Intent?)" in service
assert "stopFromNotification()" in service
assert "fun hasReport(): Boolean" in service
assert "SCREEN_OFF_CANCELLED_BEFORE_START" in service
assert "ACTION_BOOT_COMPLETED" not in service
assert "START_STICKY" not in service.replace("START_NOT_STICKY", "")
assert "android.permission.SYSTEM_ALERT_WINDOW" not in patch
assert "android.permission.DISABLE_KEYGUARD" not in patch

for text in (
    "ChappyCameraService.beginVisible(",
    "ChappyCameraService.requestStop()",
    "ChappyCameraService.hasReport()",
    "ChappyCameraService.isActive()",
    "val screenOff = call.argument<Boolean>(\"screenOff\") == true",
    "Manifest.permission.POST_NOTIFICATIONS",
):
    assert text in activity, text

for text in (
    "_screenOffVideo",
    "final screenOff = options['screenOff'] == true",
    "if (!keepRecording)",
    "if (_screenOffVideo)",
    "'screenOff': screenOff",
    "if (screenOff) 'notifications'",
    "'画面OFFや他アプリ中も録画が続きます。",
):
    assert text in runner, text
for text in (
    'id="recordScreenOff"',
    "screenOffSupported",
    "screenOffSession",
    "startDarkRecording(true)",
    "recording && video && !screenOffSession",
):
    assert text in html, text
assert "ChappyCameraService.kt" in patch
assert "'camera|microphone'" in patch
assert "'false'" in patch
for perm in ("FOREGROUND_SERVICE_CAMERA", "FOREGROUND_SERVICE_MICROPHONE",
             "POST_NOTIFICATIONS"):
    assert perm in patch
assert "private val context: Context" in recorder
assert "private val onFinalized: (() -> Unit)?" in recorder
assert "onFinalized?.invoke()" in recorder
assert "CameraX" in recorder
print("CAMREC-14 static camera FGS / notification / consent / lifecycle contract passed")

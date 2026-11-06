"""Static safety tests for first-stage mini-app motion/haptics and MP4 export.

These checks are intentionally additional to actual Flutter/Gradle compilation.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def load(relative):
    return (ROOT / relative).read_text(encoding="utf-8")

host = load("tools/android/MainActivity.kt")
devices = load("tools/android/NativeMiniAppDevices.kt")
exporter = load("tools/android/NativeVideoExport.kt")
camera = load("tools/android/NativeVideoRecorder.kt")
runner = load("lib/screens/app_runner_page.dart")
bridge = load("lib/core/local_app_server.dart")
manifest = load("tools/patch_android.py")
package = load("lib/core/package_model.dart")

for item in ("sampleMotion", "playHaptic", "exportPrivateVideo"):
    assert f'"{item}"' in host, item
for api in ("motion.sample", "haptics.play", "video.export"):
    assert f"'{api}'" in runner, api
    assert f"'{api}'" in bridge, api
for token in ("'motion'", "'haptics'", "supportedChappyPermissions"):
    assert token in package

assert "_approveNativeCapability('motion', '動きセンサー')" in runner
assert "_approveNativeCapability('haptics', '振動')" in runner
assert "widget.app.permissions.contains(capability)" in runner
assert "_approvedNativeCapabilities.clear()" in runner
assert "Sensor samples are rate-limited to 10 Hz" in runner
assert "ModalRoute.of(context)?.isCurrent != true" in runner

for token in ("Sensor.TYPE_ACCELEROMETER", "Sensor.TYPE_GYROSCOPE",
              "Sensor.TYPE_MAGNETIC_FIELD", "unregisterListener",
              "handler.postDelayed(timeout, 1500L)",
              "lastHapticAt < 120L", "VibrationEffect.createPredefined",
              "motor.hasVibrator()", "fun onPause()"):
    assert token in devices
for token in ("Sensor.TYPE_GRAVITY", "Sensor.TYPE_LINEAR_ACCELERATION",
              "fun availableSensors()", "fun hasHapticMotor()",
              "foreground &&", "vibrationMotor()"):
    assert token in devices, token
assert '"availableMotionSensors"' in host
assert '"hasHapticMotor"' in host
assert "'motion.available'" in runner and "'motion.available'" in bridge
assert "'haptics.available'" in runner and "'haptics.available'" in bridge
assert "'gravity', 'linearAcceleration'" in runner
assert "await _approveNativeCapability('motion', '動きセンサー')" in runner
assert "await _approveNativeCapability('haptics', '振動')" in runner
assert "activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager" in devices
assert "by lazy" in devices, "Do not request Android services before Activity.attach()"
assert "location" not in devices.lower()
assert "registerListener" in devices
assert "onResume()" in host and "miniDevices.onResume()" in host
assert "miniDevices.onPause()" in host

assert "Intent.ACTION_CREATE_DOCUMENT" in exporter
assert 'type = "video/mp4"' in exporter
assert "videoExporter.onResult(requestCode, resultCode, data)" in host
assert "readHash" in exporter and "originalHash" in exporter
assert "contentEquals(readHash.digest())" in exporter
assert "privateExportSource" in camera
assert "file.parentFile != root" in camera
assert "privateDirectory(appId).canonicalFile" in camera
assert "VIDEO_EXPORT_BUSY" in exporter
assert "android.permission.VIBRATE" in manifest
assert "FOREGROUND_SERVICE_CAMERA" not in manifest
assert "FOREGROUND_SERVICE_MICROPHONE" not in manifest

print("Native motion/haptics/video-export capability static safety tests passed")

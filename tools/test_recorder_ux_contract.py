"""CAMREC-15 UI/consent contract: source-only, not a real Android recording test."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def read(path): return (ROOT / path).read_text(encoding="utf-8")

html = read("sample_apps/video_recorder/index.html")
runner = read("lib/screens/app_runner_page.dart")
native = read("tools/android/MainActivity.kt")
native_prefs = read("tools/android/RecorderConfirmationPreferences.kt")
recorder = read("tools/android/NativeVideoRecorder.kt")
service = read("tools/android/ChappyCameraService.kt")
bridge = read("lib/core/local_app_server.dart")
catalog = read("lib/screens/chappy_catalog_page.dart")
qa = read("tools/test_chappy_recorder.js")

# Default pause-on-no-motion and five-second stillness, and all layers accept 5.
assert '<option value="pause" selected>' in html
assert '<option value="5" selected>' in html
assert "motionIdleSeconds < 5" in runner
assert "requestedIdleSeconds !in 5..300" in recorder
assert "idleSeconds !in 5..300" in service

# The storage card is smaller, the smart panel is collapsed below the library.
assert 'class="card capacity-card"' in html
assert '#smartSettingsPanel[hidden]' in html
assert 'id="smartSettingsPanel" hidden' in html
assert 'id="toggleSmartSettings"' in html
assert html.index('id="toggleLibrary"') < html.index('id="toggleSmartSettings"')

# A mini-app cannot disable the host consent prompt in video.start options.
assert "'readRecorderConfirmPreference'" in runner
assert "'writeRecorderConfirmPreference'" in runner
assert '"readRecorderConfirmPreference"' in native
assert '"writeRecorderConfirmPreference"' in native
assert 'getBoolean(KEY, true)' in native_prefs
assert 'getSharedPreferences' in native_prefs
assert 'RecorderConfirmationPreferences.askEveryTime(this)' in native
assert 'RecorderConfirmationPreferences.save(this, ask)' in native
assert 'widget.app.id != \'local.chappy.recorder\'' in runner
assert "showDialog<bool>" in runner
assert "毎回の録画確認を省略" in runner
assert 'readRecorderConfirmPreference' in runner.split("Future<Map<String, dynamic>> _startNativeVideo")[1]
assert 'video.confirmation.get' in runner and 'video.confirmation.set' in runner
assert 'video.confirmation.get' in bridge and 'video.confirmation.set' in bridge
assert "askEveryTime" not in runner.split("final lens = options['lens']")[0].split("_startNativeVideo")[1].split("final lens = options['lens']")[0]
assert "requestMediaPermissions" in runner
assert "canRequestChappyMedia(widget.app.permissions" in runner
assert "nativeVideo.start" in native and "ChappyCameraService.beginVisible" in native

# Toggle is in the catalog header, not hidden in individual cards.
assert "_showDescriptions" in catalog
assert "Icons.visibility_outlined" in catalog
assert "if (_showDescriptions)" in catalog
assert "各ミニアプリの説明を非表示" in catalog
assert "assert.equal(get('motionIdle').value,'5')" in qa
print("CAMREC-15 UI and host-owned recorder approval safety contract passed")

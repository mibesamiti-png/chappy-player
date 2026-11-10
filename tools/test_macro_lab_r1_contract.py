"""Macro Lab R1 static privacy and scope regression checks (no Android SDK)."""
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
native = (ROOT / "tools/android/ChappyMacroAccessibilityService.kt").read_text(encoding="utf-8")
activity = (ROOT / "tools/android/ChappyMacroLabActivity.kt").read_text(encoding="utf-8")
main = (ROOT / "tools/android/MainActivity.kt").read_text(encoding="utf-8")
flutter_home = (ROOT / "lib/main.dart").read_text(encoding="utf-8")
runner = (ROOT / "lib/screens/app_runner_page.dart").read_text(encoding="utf-8")
boot = (ROOT / "lib/core/local_app_server.dart").read_text(encoding="utf-8")
patch = (ROOT / "tools/patch_android.py").read_text(encoding="utf-8")
config = ET.parse(ROOT / "tools/android/chappy_macro_accessibility_config.xml").getroot()
ns = "{http://schemas.android.com/apk/res/android}"

assert config.tag == "accessibility-service"
assert config.get(ns + "canPerformGestures") == "false"
assert config.get(ns + "canRetrieveWindowContent") == "true"
assert config.get(ns + "isAccessibilityTool") == "false"
assert "android.permission.BIND_ACCESSIBILITY_SERVICE" in patch
assert "'{%s}exported' % android_ns: 'true'" in patch
assert "'{%s}exported' % android_ns: 'false'" in patch
assert "ChappyMacroAccessibilityService.kt" in patch
assert "ChappyMacroLabActivity.kt" in patch
assert "chappy_macro_accessibility_config.xml" in patch
assert "packageNames = arrayOf(packageName)" in native
assert "root.packageName?.toString() != packageName" in native
assert "node.packageName?.toString() == packageName" in native
assert "target(root, FIXTURE_MARKER)" in native
assert "target(root, TAP_MARKER)" in native
assert "target(updated, INPUT_MARKER)" in native
assert "onAccessibilityEvent(event: AccessibilityEvent?)" in native
assert "ACTION_CLICK" in native and "ACTION_SET_TEXT" in native
assert "fun cancel()" in native and "handler.removeCallbacksAndMessages(null)" in native
assert "startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))" in activity
assert "ChappyMacroAccessibilityService.active()?.cancel()" in activity
assert 'text = "緊急停止（いつでも）"' in activity
assert 'call.method != "openFixture"' in main
assert "ChappyMacroLabActivity::class.java" in main
assert "home_macro_lab_r1" in flutter_home
assert "'dev.chappy.player/macro_lab'" not in runner
assert "'dev.chappy.player/macro_lab'" not in boot
for forbidden in ["dispatchGesture(", "performGlobalAction(", "MediaProjection",
                  "getInstalledPackages(", "getText()"]:
    assert forbidden not in native
print("Macro Lab R1 self-only opt-in accessibility contract passed")

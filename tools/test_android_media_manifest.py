"""Smoke-test Android media permission patch without Flutter/Android SDK.

The patch must keep runtime camera/microphone consent AND add the normal
MODIFY_AUDIO_SETTINGS permission to unblock some Android WebRTC audio inputs.
No native recording API or background capture permission is exposed.
"""
from pathlib import Path
import subprocess
import sys
import tempfile
from xml.etree import ElementTree as ET

PROJECT = Path(__file__).resolve().parent.parent
ANDROID = "{http://schemas.android.com/apk/res/android}"

with tempfile.TemporaryDirectory(prefix="chappy_media_manifest_") as root_name:
    root = Path(root_name)
    manifest = root / "android/app/src/main/AndroidManifest.xml"
    manifest.parent.mkdir(parents=True)
    manifest.write_text(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
        '<application><activity android:name=".MainActivity" /></application>'
        '</manifest>',
        encoding="utf-8",
    )
    kotlin = root / "android/app/src/main/kotlin/dev/chappy/chappy_player/MainActivity.kt"
    kotlin.parent.mkdir(parents=True)
    kotlin.write_text("package dev.chappy.chappy_player\n", encoding="utf-8")
    templates = root / "tools/android"
    templates.mkdir(parents=True)
    for name in ["MainActivity.kt", "chappy_update_paths.xml",
                 "NativeMicCapture.kt"]:
        (templates / name).write_bytes(
            (PROJECT / "tools/android" / name).read_bytes()
        )
    for _ in range(2):
        subprocess.run(
            [sys.executable, str(PROJECT / "tools/patch_android.py")],
            cwd=root, capture_output=True, text=True, check=True,
        )
    native_class = root / "android/app/src/main/kotlin/dev/chappy/chappy_player/NativeMicCapture.kt"
    assert native_class.read_bytes() == (
        PROJECT / "tools/android/NativeMicCapture.kt"
    ).read_bytes()
    parsed = ET.parse(manifest).getroot()
    actual = [
        node.get(ANDROID + "name")
        for node in parsed.findall("uses-permission")
    ]
    for permission in [
        "android.permission.INTERNET",
        "android.permission.CAMERA",
        "android.permission.RECORD_AUDIO",
        "android.permission.MODIFY_AUDIO_SETTINGS",
    ]:
        assert actual.count(permission) == 1, (permission, actual)
    assert "android.permission.FOREGROUND_SERVICE_MICROPHONE" not in actual
    assert "android.permission.FOREGROUND_SERVICE_CAMERA" not in actual
    for name in ["android.hardware.camera.any", "android.hardware.microphone"]:
        features = [
            feature for feature in parsed.findall("uses-feature")
            if feature.get(ANDROID + "name") == name
        ]
        assert len(features) == 1
        assert features[0].get(ANDROID + "required") == "false"

print("Android media manifest permission patch smoke test passed")

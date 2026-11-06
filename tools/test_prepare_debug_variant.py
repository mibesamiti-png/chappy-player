"""Test debug-only package/launcher identity without Android SDK."""
from pathlib import Path
import subprocess
import sys
import tempfile
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "tools/prepare_debug_variant.py"
ANDROID = "{http://schemas.android.com/apk/res/android}"

for kotlin in [True, False]:
    with tempfile.TemporaryDirectory(prefix="chappy_debug_isolation_") as tmp:
        root = Path(tmp)
        app = root / "android/app"
        app.mkdir(parents=True)
        gradle = app / ("build.gradle.kts" if kotlin else "build.gradle")
        original = (
            'android {\n buildTypes {\n  release { signingConfig = signingConfigs.getByName("debug") }\n }\n}\n'
            if kotlin else
            "android {\n buildTypes {\n  release { signingConfig signingConfigs.debug }\n }\n}\n"
        )
        gradle.write_text(original, encoding="utf-8")
        manifest = app / "src/main/AndroidManifest.xml"
        manifest.parent.mkdir(parents=True)
        manifest.write_text(
            '<?xml version="1.0" encoding="utf-8"?>'
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
            '<application android:label="Chappy Player" /></manifest>',
            encoding="utf-8",
        )
        for _ in range(2):
            subprocess.run(
                [sys.executable, str(SCRIPT)],
                cwd=root, capture_output=True, text=True, check=True,
            )
        patched = gradle.read_text(encoding="utf-8")
        suffix = ('applicationIdSuffix = ".debug"' if kotlin
                  else "applicationIdSuffix '.debug'")
        assert patched.count(suffix) == 1
        assert patched.count("versionNameSuffix") == 1
        assert "release" in patched
        assert "signingConfig" in patched
        root_xml = ET.parse(manifest).getroot()
        assert root_xml.find("application").get(ANDROID + "label") == "Chappy Player Debug"

print("Debug package isolation and non-destructive manifest patch tests passed")

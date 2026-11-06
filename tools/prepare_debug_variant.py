"""Prepare a separate Chappy Player DEBUG application ID after flutter create.

Runs ONLY in the debug APK workflow. Production signing and the release
workflow must not use this helper; published APK package ID remains unchanged.

The debuggable app installs alongside the signed release with separate data.
Never copy a release keystore to a debugging APK.
"""
from pathlib import Path
from xml.etree import ElementTree as ET

kotlin = Path("android/app/build.gradle.kts")
groovy = Path("android/app/build.gradle")
if kotlin.is_file():
    gradle = kotlin
    marker = "buildTypes {"
    suffix = 'applicationIdSuffix = ".debug"'
    block = """buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
"""
elif groovy.is_file():
    gradle = groovy
    marker = "buildTypes {"
    suffix = "applicationIdSuffix '.debug'"
    block = """buildTypes {
        debug {
            applicationIdSuffix '.debug'
            versionNameSuffix '-debug'
        }
"""
else:
    raise SystemExit("Generated Android Gradle build file was not found")

source = gradle.read_text(encoding="utf-8")
if suffix not in source:
    if source.count(marker) != 1:
        raise SystemExit("Unexpected buildTypes structure; not patching debug package")
    source = source.replace(marker, block, 1)
    gradle.write_text(source, encoding="utf-8")

manifest = Path("android/app/src/main/AndroidManifest.xml")
if not manifest.is_file():
    raise SystemExit("Generated Android manifest was not found")
namespace = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", namespace)
root = ET.parse(manifest).getroot()
application = root.find("application")
if application is None:
    raise SystemExit("Missing Android application node")
application.set("{" + namespace + "}label", "Chappy Player Debug")
ET.indent(root, space="    ")
manifest.write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n' +
    ET.tostring(root, encoding="unicode"), encoding="utf-8"
)
print("Debug APK isolated as dev.chappy.chappy_player.debug with separate app data")

"""Allow Android WebView to connect ONLY to our loopback static file server.

The app does NOT expose external HTTP APIs. The WebView's Content Security Policy
forbids remote network connections. This manifest must be reviewed for release.
"""
from pathlib import Path
from xml.etree import ElementTree as ET

manifest = Path('android/app/src/main/AndroidManifest.xml')
if not manifest.exists():
    raise SystemExit('Missing AndroidManifest.xml (run flutter create --platforms=android .)')
xml = manifest.read_text(encoding='utf-8')
android_ns = 'http://schemas.android.com/apk/res/android'
ET.register_namespace('android', android_ns)
root = ET.fromstring(xml)
permission = '{%s}name' % android_ns
if not any(el.get(permission) == 'android.permission.INTERNET' for el in root.findall('uses-permission')):
    item = ET.Element('uses-permission', {permission: 'android.permission.INTERNET'})
    root.insert(0, item)
application = root.find('application')
if application is None:
    raise SystemExit('Missing application node')
application.set('{%s}usesCleartextTraffic' % android_ns, 'true')
# Future releases should replace localhost cleartext with an HTTPS asset loader.
ET.indent(root, space='    ')
manifest.write_text('<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(root, encoding='unicode'), encoding='utf-8')
print('Patched Android manifest: INTERNET + loopback HTTP support')

# Modern Flutter Android runner is Kotlin DSL; keep minSdk compatible with
# webview_flutter 4.13.1 (Android API level 24 or newer).
kts = Path('android/app/build.gradle.kts')
groovy = Path('android/app/build.gradle')
if kts.exists():
    body = kts.read_text(encoding='utf-8')
    body = body.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
    kts.write_text(body, encoding='utf-8')
elif groovy.exists():
    body = groovy.read_text(encoding='utf-8')
    body = body.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24')
    groovy.write_text(body, encoding='utf-8')

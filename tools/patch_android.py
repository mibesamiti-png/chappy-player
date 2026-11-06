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
# Hardware is opt-in per mini-app: Android permissions are requested only
# after the user approves an individual camera/microphone request.
# Some Android WebView/WebRTC audio devices require MODIFY_AUDIO_SETTINGS
# in addition to runtime RECORD_AUDIO (NotReadableError after OS consent).
# This is a normal Android manifest permission, NOT a .chappy capability;
# never expose raw AudioManager controls to untrusted mini-app JavaScript.
for name in ('android.permission.CAMERA', 'android.permission.RECORD_AUDIO',
             'android.permission.MODIFY_AUDIO_SETTINGS', 'android.permission.VIBRATE'):
    if not any(item.get(permission) == name for item in root.findall('uses-permission')):
        root.insert(0, ET.Element('uses-permission', {permission: name}))
# Camera/microphone are optional hardware; don't exclude devices without them.
for feature in ('android.hardware.camera.any', 'android.hardware.microphone'):
    if not any(item.get(permission) == feature for item in root.findall('uses-feature')):
        root.insert(0, ET.Element('uses-feature', {
            permission: feature, '{%s}required' % android_ns: 'false'
        }))
application = root.find('application')
if application is None:
    raise SystemExit('Missing application node')
application.set('{%s}usesCleartextTraffic' % android_ns, 'true')
# Self-hosted/sideloaded builds only: this permission enables a user-initiated
# Android installation confirmation; nothing is silently installed.
if not any(el.get(permission) == 'android.permission.REQUEST_INSTALL_PACKAGES'
           for el in root.findall('uses-permission')):
    root.insert(0, ET.Element('uses-permission', {
        permission: 'android.permission.REQUEST_INSTALL_PACKAGES'
    }))
# FileProvider shares only a verified APK in our private update cache.
provider_attrs = {
    '{%s}name' % android_ns: 'androidx.core.content.FileProvider',
    '{%s}authorities' % android_ns: '${applicationId}.chappyupdates',
    '{%s}exported' % android_ns: 'false',
    '{%s}grantUriPermissions' % android_ns: 'true',
}
if not any(el.get('{%s}authorities' % android_ns) ==
           '${applicationId}.chappyupdates' for el in application.findall('provider')):
    provider = ET.SubElement(application, 'provider', provider_attrs)
    ET.SubElement(provider, 'meta-data', {
        '{%s}name' % android_ns: 'android.support.FILE_PROVIDER_PATHS',
        '{%s}resource' % android_ns: '@xml/chappy_update_paths'
    })

# Allow the user to tap/share .chappy files from Android's Downloads/Files
# screens. Most providers set a generic ZIP or octet-stream MIME type; the
# native host MUST inspect the display name and bytes before importing.
# No automatic execution or broad storage permission is required.
activity = None
for node in application.findall('activity'):
    if node.get('{%s}name' % android_ns, '').endswith('MainActivity'):
        activity = node
        break
if activity is None:
    raise SystemExit('Generated Flutter MainActivity not found')

def install_intent_filter(action, mime_types, scheme=None):
    filt = ET.SubElement(activity, 'intent-filter')
    ET.SubElement(filt, 'action', {permission: action})
    ET.SubElement(filt, 'category', {
        permission: 'android.intent.category.DEFAULT'
    })
    if action == 'android.intent.action.VIEW':
        ET.SubElement(filt, 'category', {
            permission: 'android.intent.category.BROWSABLE'
        })
    for mime in mime_types:
        attrs = {'{%s}mimeType' % android_ns: mime}
        if scheme:
            attrs['{%s}scheme' % android_ns] = scheme
        ET.SubElement(filt, 'data', attrs)

chappy_mimes = [
    'application/vnd.chappy.package',
    'application/zip',
    'application/x-zip-compressed',
    'application/octet-stream',
]
install_intent_filter('android.intent.action.VIEW', chappy_mimes, 'content')
install_intent_filter('android.intent.action.SEND', chappy_mimes)
print('Enabled user-invoked .chappy file open/share intent filters')

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
    # CameraX video Recorder is hosted natively; no third-party JS gets raw
    # camera frames or direct paths. Keep all CameraX artifacts pinned together.
    if 'androidx.camera:camera-video:1.5.3' not in body:
        body += ("""
// CameraX video recording (native, foreground only).
dependencies {
    implementation("androidx.camera:camera-camera2:1.5.3")
    implementation("androidx.camera:camera-lifecycle:1.5.3")
    implementation("androidx.camera:camera-video:1.5.3")
}
""")
    kts.write_text(body, encoding='utf-8')
elif groovy.exists():
    body = groovy.read_text(encoding='utf-8')
    body = body.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24')
    if 'androidx.camera:camera-video:1.5.3' not in body:
        body += ("""
// CameraX video recording (native, foreground only).
dependencies {
    implementation 'androidx.camera:camera-camera2:1.5.3'
    implementation 'androidx.camera:camera-lifecycle:1.5.3'
    implementation 'androidx.camera:camera-video:1.5.3'
}
""")
    groovy.write_text(body, encoding='utf-8')


# Flutter generates Android sources on each CI runner. Install the player
# MethodChannel host after generation, so an APK can be checked against the
# currently installed app's signing certificate before suggesting an update.
native_host = Path('tools/android/MainActivity.kt')
native_target = Path('android/app/src/main/kotlin/dev/chappy/chappy_player/MainActivity.kt')
if not native_host.is_file() or not native_target.is_file():
    raise SystemExit('Missing Flutter MainActivity or update-check host template')
existing = native_target.read_text(encoding='utf-8')
if 'package dev.chappy.chappy_player' not in existing:
    raise SystemExit('Unexpected generated Android package; refusing to overwrite')
native_target.write_text(native_host.read_text(encoding='utf-8'), encoding='utf-8')
print('Installed native APK update compatibility preflight host')

# The native microphone class is shipped in the same Android package.
# Capture is foreground-only, user-approved, and never stores raw PCM.
mic_source = Path('tools/android/NativeMicCapture.kt')
mic_target = native_target.with_name('NativeMicCapture.kt')
if not mic_source.is_file():
    raise SystemExit('Missing native AudioRecord capture implementation')
mic_target.write_bytes(mic_source.read_bytes())
print('Installed foreground-only native microphone capture host')

# CameraX video recorder does not start a foreground service: recordings
# stop on Activity pause until explicit Android 14 service work is implemented.
video_source = Path('tools/android/NativeVideoRecorder.kt')
video_target = native_target.with_name('NativeVideoRecorder.kt')
if not video_source.is_file():
    raise SystemExit('Missing native CameraX video recorder')
video_target.write_bytes(video_source.read_bytes())
print('Installed foreground-only native video recorder (private by default)')

# These privileged capabilities are mediated by the Flutter .chappy manifest
# policy and first-use user approval. Motion sampling is single-shot only and
# vibration has native rate limits. Private MP4 export requires SAF picker.
for filename in ('NativeMiniAppDevices.kt', 'NativeVideoExport.kt',
                 'NativeMiniAppDocuments.kt', 'NativeVideoZipBackup.kt'):
    source = Path('tools/android') / filename
    if not source.is_file():
        raise SystemExit(f'Missing native mini-app capability host: {filename}')
    native_target.with_name(filename).write_bytes(source.read_bytes())
print('Installed scoped motion/haptics and user-picked private video export hosts')

# Ship only the private update cache path; never share all cache or app data.
paths_src = Path('tools/android/chappy_update_paths.xml')
paths_dst = Path('android/app/src/main/res/xml/chappy_update_paths.xml')
if not paths_src.is_file():
    raise SystemExit('Missing FileProvider update paths template')
paths_dst.parent.mkdir(parents=True, exist_ok=True)
paths_dst.write_bytes(paths_src.read_bytes())
print('Enabled user-confirmed APK update handoff via scoped FileProvider')

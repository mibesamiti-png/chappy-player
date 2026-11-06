"""Static, offline boundary tests for Android user-picked text documents.

Additional to the Kotlin compilation and Flutter JS bridge smoke tests.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def read(name):
    return (ROOT / name).read_text(encoding="utf-8")

native = read("tools/android/NativeMiniAppDocuments.kt")
activity = read("tools/android/MainActivity.kt")
flutter = read("lib/screens/app_runner_page.dart")
bridge = read("lib/core/local_app_server.dart")
patch = read("tools/patch_android.py")
model = read("lib/core/package_model.dart")
builder = read("tools/build_chappy_catalog.py")
packer = read("tools/pack_html_chappy.py")

for name in ("Intent.ACTION_OPEN_DOCUMENT", "Intent.ACTION_CREATE_DOCUMENT",
             "Intent.CATEGORY_OPENABLE", "ContentEquals", "MAX_TEXT_BYTES"):
    if name == "ContentEquals":
        assert "contentEquals(expected)" in native
    else:
        assert name in native
assert "MAX_TEXT_BYTES = 64 * 1024" in native
assert "data?.data" in native and 'uri.scheme != "content"' in native
assert "readback" in native and "SHA-256" in native
assert 'raw.contentEquals(text.toByteArray(Charsets.UTF_8))' in native
assert "openInputStream(uri)" in native
assert "openOutputStream(uri, \"wt\")" in native
assert "input.use" in native and "output.use" in native
assert "private" in native
assert "NativeMiniAppDocuments.kt" in patch
assert "miniDocuments.pickText(result)" in activity
assert "miniDocuments.saveText(fileName, contents, result)" in activity
assert "miniDocuments.onResult(requestCode, resultCode, data)" in activity
assert "if (!micActivityVisible)" in activity
assert "_approveNativeCapability('files', 'ファイルの選択・保存')" in flutter
assert "widget.app.permissions.contains(capability)" in flutter
assert "utf8.encode(text).length > 32 * 1024" in flutter
assert "case 'files.pickText':" in flutter
assert "case 'files.saveText':" in flutter
assert "files: Object.freeze({" in bridge
assert "pickText: () => call('files.pickText', {})" in bridge
assert "call('files.saveText', {fileName: String(fileName), text: String(text)})" in bridge
assert "connect-src 'none'" in bridge
assert "'files'" in model and "'files'" in packer and '"files"' in builder

print("Android SAF user-picked text read/write capability contract passed")

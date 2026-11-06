"""Binary SAF mini-app vault contract and independent archive/file fixture checks.

These tests do not pretend to execute Android Kotlin. CI must compile the app.
"""
from pathlib import Path
import hashlib
import re
import tempfile

ROOT = Path(__file__).resolve().parent.parent
def read(path): return (ROOT / path).read_text(encoding="utf-8")
native = read("tools/android/NativeMiniAppAssets.kt")
host = read("tools/android/MainActivity.kt")
runner = read("lib/screens/app_runner_page.dart")
bridge = read("lib/core/local_app_server.dart")
patch = read("tools/patch_android.py")
ui = read("sample_apps/file_lab/index.html")

for token in (
    "Intent.ACTION_OPEN_DOCUMENT", "Intent.ACTION_CREATE_DOCUMENT",
    "Intent.CATEGORY_OPENABLE", 'type = "*/*"',
    'MAX_FILE_BYTES = 256L * 1024 * 1024',
    'MAX_STORE_BYTES = 512L * 1024 * 1024',
    'MAX_FILES = 32',
    'Regex("^[a-f0-9]{32}$")',
    'ownerPattern.matches(owner)',
    'root.parentFile != parent',
    'f.parentFile != root',
    'FileOutputStream(staging)',
    'target.fd.sync()',
    'sourceHash.digest()',
    'destinationHash.digest()',
    'sourceDigest.contentEquals(destinationHash.digest())',
    'contentResolver.openInputStream(uri)',
    'contentResolver.openOutputStream(uri, "w")',
    'private_assets',
    'AlertDialog.Builder(activity)',
    'setPositiveButton("削除する")',
    'setNegativeButton("キャンセル")',
    'fun onDestroy()',
):
    assert token in native, token

for token in ('"importBinaryAsset"', '"listBinaryAssets"',
              '"exportBinaryAsset"', '"deleteBinaryAsset"',
              'miniAssets.importAsset(', 'miniAssets.list(',
              'miniAssets.exportAsset(', 'miniAssets.deleteAsset(',
              'miniAssets.onResult(requestCode, resultCode, data)',
              'miniAssets.onDestroy()'):
    assert token in host, token
assert 'if (!micActivityVisible)' in host

for method in ('files.importAsset', 'files.listAssets',
               'files.exportAsset', 'files.deleteAsset'):
    assert f"case '{method}':" in runner, method
    assert f"'{method}'" in bridge, method
assert runner.count("await _approveNativeCapability('files', 'ファイルの選択・保存')") >= 6
assert "'owner': widget.app.id" in runner
assert "RegExp(r'^[a-f0-9]{32}$')" in runner
assert 'NativeMiniAppAssets.kt' in patch

for action in ('files.importAsset()', 'files.listAssets()',
               'files.exportAsset(file.id)', 'files.deleteAsset(file.id)'):
    assert action in ui
assert "textContent=file.name" in ui, "File names must be rendered as text"
assert "1ファイル最大256MiB" in ui
assert "合計512MiB・32ファイル" in ui

assert "MANAGE_EXTERNAL_STORAGE" not in native
assert "READ_EXTERNAL_STORAGE" not in native
assert "java.net" not in native
assert "exec(" not in native
assert "ProcessBuilder" not in native
assert "return mapOf(\"status\" to \"saved\", \"sizeBytes\"" in native
assert "openFileDescriptor" not in native

# Independently demonstrate that a binary payload can be streamed and checked
# without ever decoding or transferring it as a text/JSON message.
content = bytes(range(256)) * 2048
with tempfile.TemporaryDirectory() as folder:
    original = Path(folder) / "source.bin"
    copied = Path(folder) / "copy.bin"
    original.write_bytes(content)
    digest = hashlib.sha256()
    with original.open("rb") as source, copied.open("wb") as target:
        for block in iter(lambda: source.read(65536), b""):
            target.write(block)
            digest.update(block)
    assert copied.stat().st_size == len(content)
    assert digest.hexdigest() == hashlib.sha256(copied.read_bytes()).hexdigest()
    assert re.fullmatch(r"[a-f0-9]{64}", digest.hexdigest())
    copied.write_bytes(content[:-1])
    assert digest.hexdigest() != hashlib.sha256(copied.read_bytes()).hexdigest()

print("Native asset vault SAF permission/path/quota/integrity contracts passed")

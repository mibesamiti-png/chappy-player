"""ZIP compression contract and independent lossless reference fixtures.

Reference fixtures exercise standards-based DEFLATE properties, not Kotlin
execution. Android Gradle CI and actual Android SAF-provider tests remain separate.
"""
from pathlib import Path
import hashlib
import io
import random
import zipfile

ROOT = Path(__file__).resolve().parent.parent
def read(path): return (ROOT / path).read_text(encoding="utf-8")

native = read("tools/android/NativeMiniAppAssets.kt")
host = read("tools/android/MainActivity.kt")
runner = read("lib/screens/app_runner_page.dart")
bridge = read("lib/core/local_app_server.dart")
lab = read("sample_apps/file_lab/index.html")
unit = read("tools/test_file_lab.js")

for token in (
    'const val ZIP_REQUEST = 0x64CD',
    "Mode { IMPORT, EXPORT, EXPORT_ZIP }",
    "fun exportZip(",
    'level !in setOf(1, 6, 9)',
    'type = "application/zip"',
    "Intent.ACTION_CREATE_DOCUMENT",
    "ZipOutputStream(DigestOutputStream(output, archiveDigest))",
    "zip.setLevel(request.compressionLevel)",
    'ZipEntry("files/" + record.name)',
    'ZipEntry("manifest.json")',
    '"sourceSha256"',
    '"compressionLevel"',
    'inputDigest.digest().contentEquals(hexBytes(record.sha))',
    'actualArchiveHash.digest()',
    'expectedArchiveHash.contentEquals(actualArchiveHash.digest())',
    'contentResolver.openInputStream(uri)',
    'checkTransferActive(request)',
    '"originalBytes" to sourceBytes',
    '"zipBytes" to zippedBytes',
    '"savedBytes" to (sourceBytes - zippedBytes)',
    '"percentSmaller" to',
    'Mode.EXPORT_ZIP -> copyOutCompressedZip(',
    '(requestCode == ZIP_REQUEST && request.mode != Mode.EXPORT_ZIP)',
    'if (request.mode != Mode.IMPORT)',
):
    assert token in native, token

assert '"exportCompressedAssetZip"' in host
assert "miniAssets.exportZip(" in host
assert "case 'files.exportCompressedZip':" in runner
assert "'owner': widget.app.id" in runner
assert "'fast': 1, 'balanced': 6, 'max': 9" in runner
assert "await _approveNativeCapability('files', 'ファイルの選択・保存')" in runner
assert "exportCompressedZip: (id, level='balanced')" in bridge
assert "'files.exportCompressedZip'" in bridge
assert "zipButton.textContent='可逆ZIPで保存'" in lab
assert "files.exportCompressedZip(file.id,levelSelect.value)" in lab
assert "75.0% 削減" in unit

assert "MANAGE_EXTERNAL_STORAGE" not in native
assert "java.net" not in native
assert "ProcessBuilder" not in native
assert "FileOutputStream(uri" not in native

# Make deterministic independent test archives, then restore their exact bytes.
# The UI must not imply that all files necessarily become smaller.
fixtures = [
    (b"CHAPPY-ASSET-COMPRESSION-TEST\n" * 10000, True),
    (random.Random(20261107).randbytes(128 * 1024), False),
]
for original, should_compress in fixtures:
    for level in (1, 6, 9):
        output = io.BytesIO()
        manifest = ('{"schemaVersion":1,"format":"chappy-asset-zip",'
                    '"fileName":"test.bin","sourceBytes":%d,'
                    '"sourceSha256":"%s","compressionLevel":%d}'
                    % (len(original), hashlib.sha256(original).hexdigest(), level))
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED,
                             compresslevel=level) as archive:
            archive.writestr("files/test.bin", original)
            archive.writestr("manifest.json", manifest)
        encoded = output.getvalue()
        with zipfile.ZipFile(io.BytesIO(encoded)) as archive:
            assert set(archive.namelist()) == {"files/test.bin", "manifest.json"}
            assert archive.read("files/test.bin") == original
            assert archive.testzip() is None
        saved = len(original) - len(encoded)
        if should_compress:
            assert saved > 0, (level, saved)
        else:
            assert saved < 0, (level, saved)
        assert hashlib.sha256(encoded).hexdigest() == hashlib.sha256(
            output.getvalue()).hexdigest()
print("Asset ZIP compression API and independent lossless DEFLATE fixture checks passed")

"""NETLAB-03B-5: encrypted, manually approved verification history boundary.

Static checks supplement the Android build. They are not hardware AES-GCM
or real two-device QA and do not establish persistent pairing authorization.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


native = read("tools/android/NativeVerifiedPcHistory.kt")
activity = read("tools/android/MainActivity.kt")
patch = read("tools/patch_android.py")
manifest_test = read("tools/test_android_media_manifest.py")
flutter = read("lib/screens/companion_pairing_page.dart")
history = read("lib/screens/verified_pc_history_page.dart")
client = read("lib/core/verified_pc_history_client.dart")
js_bridge = read("lib/core/local_app_server.dart")
identity_page = read("lib/screens/pc_identity_page.dart")
source = read("lib/core/companion_identity_exchange.dart")

assert "'NativeVerifiedPcHistory.kt'" in patch
assert '"NativeVerifiedPcHistory.kt"' in manifest_test
assert 'NativeVerifiedPcHistory(this, pcIdentity)' in activity
for name in ("verifiedPcList", "verifiedPcRemember", "verifiedPcForget",
             "verifiedPcClear"):
    assert f'"{name}"' in activity
    assert name not in js_bridge, "No .chappy JavaScript history API"
assert 'if (!micActivityVisible)' in activity
assert 'networkDiscovery.pairingAllowed()' in activity
assert 'verifiedPcHistory.clearAll()' in activity
assert 'if (call.arguments != null)' in activity, "Reject fake clear arguments"
for item in (
    'KeyStore.getInstance("AndroidKeyStore")',
    'KeyProperties.KEY_ALGORITHM_AES',
    'KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT',
    'KeyProperties.BLOCK_MODE_GCM',
    'KeyProperties.ENCRYPTION_PADDING_NONE',
    'setRandomizedEncryptionRequired(true)',
    'Cipher.getInstance("AES/GCM/NoPadding")',
    'GCMParameterSpec(128, encrypted.copyOfRange(0, NONCE_SIZE))',
    'private const val MAX_RECORDS = 24',
    'private const val MAX_BLOB = 8192',
    'AtomicFile(File(context.filesDir, "verified-pc-history-v1.aesgcm"))',
    'require(document.getString("owner") == ownerFp)',
    'file.startWrite()',
    'file.finishWrite(stream)',
    'file.failWrite(stream)',
):
    assert item in native, item
for forbidden in (
    "Socket(", "HttpClient", "OkHttp", "ProcessBuilder", "exec(",
    "DevicePolicyManager", "getExternalFilesDir", "SharedPreferences",
):
    assert forbidden not in native, forbidden
assert "remember(" not in source and "verifiedPc" not in source, (
    "Do not silently persist or automatically trust successful QR-v3 exchange"
)
for pattern in (
    "if (_verified && _invite?.pcIdentityFingerprint != null)",
    "if (_busy || _savingHistory || _savedHistory || !_verified",
    "showDialog<bool>(",
    "await _verifiedHistory.remember(fp)",
    "confirmationCode(nonce)",
):
    assert pattern in flutter, pattern
# Android QR-v3 can only be submitted once per scan; no stale UI reuse.
for token in (
    "bool _qrConsumed = false",
    "if (invite != null) _qrConsumed = true",
    "generation != _generation || invite == null",
    "_identityExchange.cancel();",
    "if (_invite != null) _fingerprint.clear();",
    "final generation = _generation;",
    "if (!mounted || consent != true || generation != _generation",
    "(_invite != null && _qrConsumed)",
    "pair_qr_consumed",
):
    assert token in flutter, token
assert "verified_pc_history_page.dart" in identity_page
assert "この記録を削除" in history
assert "verifiedPcForget" in client and "verifiedPcList" in client
assert "verifiedPcClear" in client and "clear() =>" in client
assert "verified_pc_clear_all" in history
assert "verified_pc_clear_confirm" in history
assert "すべてのPC確認履歴を削除" in history
print("Encrypted public-fingerprint history: explicit UI, private storage, no authorization")

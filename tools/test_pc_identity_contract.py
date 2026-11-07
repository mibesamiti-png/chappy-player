"""NETLAB-03B-2 identity foundation trust-boundary regression.

Static source checks supplement (but cannot replace) real Android Keystore
tests on hardware and real Windows DPAPI CI. No stored connection authority.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def read(name: str) -> str:
    return (ROOT / name).read_text(encoding="utf-8")

android = read("tools/android/NativePcIdentity.kt")
host = read("tools/android/MainActivity.kt")
patch = read("tools/patch_android.py")
dart = read("lib/core/pc_identity_client.dart")
screen = read("lib/screens/pc_identity_page.dart")
netlab = read("lib/screens/network_lab_page.dart")
bridge = read("lib/core/local_app_server.dart")
windows = read("examples/windows_companion/windows_identity.py")
companion = read("examples/windows_companion/companion.py")

for text in (
    'KeyPairGenerator.getInstance(',
    'KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore"',
    'KeyGenParameterSpec.Builder(',
    'ECGenParameterSpec("secp256r1")',
    'KeyProperties.PURPOSE_SIGN',
    'KeyProperties.DIGEST_SHA256',
    'KeyStore.getInstance("AndroidKeyStore")',
    "keyStore.deleteEntry(ALIAS)",
    'if (store().containsAlias(ALIAS))',
):
    assert text in android, text
for forbidden in ("getPrivate", "getKey(", "privateKey.encoded",
                  "Signature.getInstance(", "SharedPreferences", "File("):
    assert forbidden not in android, forbidden

assert '"NativePcIdentity.kt"' not in bridge
assert "'NativePcIdentity.kt'" in patch
assert "private val pcIdentity = NativePcIdentity()" in host
for name in ("pcIdentityStatus", "pcIdentityCreate", "pcIdentityRevoke"):
    assert f'"{name}"' in host and f"'{name}'" in dart, name
    assert name not in bridge, "No .chappy JavaScript access to device keys"
assert "if (!micActivityVisible)" in host
assert "NETLAB_NOT_FOREGROUND" in host

# Destructive Android key deletion requires the exact key the user reviewed,
# with host argument validation and an independent native precondition.
for token in (
    'fun revoke(expectedFingerprint: String)',
    'currentFingerprint == expectedFingerprint',
    'Regex("^[0-9a-f]{64}$").matches(expectedFingerprint)',
):
    assert token in android, token
for token in (
    'val args = call.arguments as? Map<*, *>',
    'args.size == 1 && args["fingerprint"] is String',
    'pcIdentity.revoke(expectedFingerprint)',
    'if (revoked) verifiedPcHistory.clearAll()',
):
    assert token in host, token
for token in (
    'Future<bool> revoke(String expectedFingerprint)',
    "'pcIdentityRevoke',",
    "'fingerprint': expectedFingerprint",
):
    assert token in dart, token
for token in (
    "'pc_identity_revoke_suffix'",
    "'pc_identity_revoke_confirm'",
    'confirmationGeneration != _generation',
    '_identity?.fingerprint != fingerprint',
    'entered == suffix',
    'widget.client.revoke(fingerprint)',
):
    assert token in screen, token

for token in (
    "showDialog<bool>",
    "'pc_identity_create'",
    "'pc_identity_revoke'",
    "consent != true",
    "端末キーを作成",
    "秘密鍵を削除",
    "永続的なペアリング",
):
    assert token in screen, token
assert "確認済みPCの記録を確認・削除" in screen
assert "const PcIdentityPage()" in netlab
assert "netlab_device_traffic" in netlab, "Keep existing phone metrics"

for token in (
    'ctypes.WinDLL("crypt32"',
    "CryptProtectData", "CryptUnprotectData",
    "CRYPTPROTECT_UI_FORBIDDEN",
    "os.fsync(output.fileno())",
    'path.open("xb")',
    'PLAINTEXT_PREFIX',
    "ec.generate_private_key(ec.SECP256R1())",
    'serialization.Encoding.DER',
    'serialization.PublicFormat.SubjectPublicKeyInfo',
    "def revoke_identity(",
):
    assert token in windows, token
assert windows.count("CRYPTPROTECT_LOCAL_MACHINE") == 1, (
    "The only LOCAL_MACHINE mention must be the explicit prohibition in the docstring")
assert "CRYPTPROTECT_UI_FORBIDDEN, ctypes.byref(output_blob)" in windows
for forbidden in ("subprocess.", "socket.connect(", "requests.", "password =",
                  "BEGIN PRIVATE KEY", "print(raw)"):
    assert forbidden not in windows, forbidden
for token in (
    "--identity-create", "--identity-status", "--identity-revoke",
    'answer != "REVOKE"', "if not args.start:",
):
    assert token in companion, token
assert "windows_identity" not in bridge

print("PC identity host-only Android Keystore / Windows DPAPI boundaries passed")

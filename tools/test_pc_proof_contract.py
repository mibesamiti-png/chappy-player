"""NETLAB-03B-3: offline Android proof helper isolation/source contract.

This is NOT an on-device signature test. Android APK compilation and real
Android KeyStore + Windows pairing require separate exact-head/physical QA.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


kotlin = source("tools/android/NativePcProof.kt")
patch = source("tools/patch_android.py")
host = source("tools/android/MainActivity.kt")
js_bridge = source("lib/core/local_app_server.dart")
identity = source("tools/android/NativePcIdentity.kt")
python_proof = source("examples/windows_companion/identity_proof.py")

assert "'NativePcProof.kt'" in patch, "Install proof helper during generated Android build"
assert "NativePcProof" not in host, "No native host signing endpoint yet"
assert "NativePcProof" not in js_bridge, "Never make identity signing a mini-app capability"
for method in ("signAndroid", "verifyPeerProof", "canonicalChallenge"):
    assert method in kotlin
for token in (
    'KeyStore.getInstance("AndroidKeyStore")',
    'store.getKey(ALIAS, null) as? PrivateKey',
    'Signature.getInstance("SHA256withECDSA")',
    '"CHAPPY-NETLAB-03B-PROOF-V1"',
    'role == "pc" || role == "android"',
    'HEX16.matches(invitation)',
    'HEX32.matches(tlsFingerprint)',
    'HEX32.matches(peerFingerprint)',
    'HEX32.matches(nonce)',
    'expiresAt - nowEpochSeconds > 600L',
    'response.keys != setOf("algorithm", "spki", "signature")',
    'digestHex != expectedSignerFingerprint',
    'key.params.order != P256_ORDER',
):
    assert token in kotlin, token
assert "getKey(" not in identity, "Preserve non-signing identity status lifecycle"
assert "Signature.getInstance" not in identity
assert "pcIdentitySign" not in host
assert "pcIdentitySign" not in js_bridge
assert "sign_pc_challenge(" in python_proof
assert "verify_identity_proof(" in python_proof
assert "nonce" in python_proof and "tls_fingerprint" in python_proof
print("PC proof-only P-256 signing primitives: no MethodChannel/mini-app exposure")

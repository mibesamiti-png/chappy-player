"""Regression tests for APK signing certificate output format variations."""
from verify_signed_release import parse_apk_certificate_digests

DIGEST = "a293d8997d3bdccfa44c0c69099499baa87e23dca464829de59e929a87bfebed"

numbered = (
    "Verified using v2 scheme (APK Signature Scheme v2): true\n"
    "Number of signers: 1\n"
    "Signer #1 certificate DN: CN=Chappy Player\n"
    f"Signer #1 certificate SHA-256 digest: {DIGEST}\n"
    f"Signer #1 public key SHA-256 digest: {'b' * 64}\n"
)
assert parse_apk_certificate_digests(numbered) == [DIGEST]

# Newer build-tools can label the same signer by Android SDK version range.
sdk_range = (
    "Number of signers: 1\n"
    f"Signer (minSdkVersion=24, maxSdkVersion=32) certificate SHA-256 digest: {DIGEST}\n"
)
assert parse_apk_certificate_digests(sdk_range) == [DIGEST]

multiple_sdk_ranges = sdk_range + (
    f"Signer (minSdkVersion=33, maxSdkVersion=35) certificate SHA-256 digest: {DIGEST}\n"
)
assert parse_apk_certificate_digests(multiple_sdk_ranges) == [DIGEST, DIGEST]

# Unknown/malformed signer lines must never be silently ignored.
bad_outputs = [
    "",
    "Number of signers: 1",
    f"Signer #1 public key SHA-256 digest: {DIGEST}",
    "Signer #1 certificate SHA-256 digest: NOT_A_DIGEST",
    f"UnknownSigner certificate SHA-256 digest: {DIGEST}",
    numbered + "Signer #2 certificate SHA-256 digest: NOT_A_DIGEST",
]
for bad in bad_outputs:
    try:
        parse_apk_certificate_digests(bad)
    except RuntimeError:
        pass
    else:
        raise AssertionError("Malformed signer digest unexpectedly accepted")

print("APK signer certificate parser smoke test passed")

"""User-opted, revocable Windows PC identity for *future* mutual pairing.

The NIST P-256 signing private key is persisted exclusively as a same-Windows-
user DPAPI blob in LOCALAPPDATA. No background listener, pairing, certificate
override, telemetry or remote command is granted by the existence of this key.

This is an identity FOUNDATION, not an authenticated PC↔Android protocol.
"""
from __future__ import annotations

import ctypes
from ctypes import wintypes
import hashlib
import os
from pathlib import Path

IDENTITY_FILENAME = "device-identity-v1.dpapi"
PLAINTEXT_PREFIX = b"CHAPPY_PC_IDENTITY_P256_V1\x00"
MAX_BLOB_BYTES = 16384
CRYPTPROTECT_UI_FORBIDDEN = 0x1


class _DataBlob(ctypes.Structure):
    _fields_ = [
        ("cbData", wintypes.DWORD),
        ("pbData", ctypes.POINTER(ctypes.c_ubyte)),
    ]


def _dpapi(data: bytes, *, protect: bool) -> bytes:
    """Use current-user DPAPI; never use CRYPTPROTECT_LOCAL_MACHINE."""
    if os.name != "nt":
        raise OSError("Windows DPAPI is required")
    if not data or len(data) > MAX_BLOB_BYTES:
        raise ValueError("Unexpected PC identity length")
    raw = ctypes.create_string_buffer(data)
    input_blob = _DataBlob(
        len(data), ctypes.cast(raw, ctypes.POINTER(ctypes.c_ubyte))
    )
    output_blob = _DataBlob()
    api = ctypes.WinDLL("crypt32", use_last_error=True)
    if protect:
        fn = api.CryptProtectData
        fn.argtypes = [
            ctypes.POINTER(_DataBlob), wintypes.LPCWSTR,
            ctypes.POINTER(_DataBlob), ctypes.c_void_p, ctypes.c_void_p,
            wintypes.DWORD, ctypes.POINTER(_DataBlob),
        ]
        args = (
            ctypes.byref(input_blob), "Chappy PC identity (user-only)", None,
            None, None, CRYPTPROTECT_UI_FORBIDDEN, ctypes.byref(output_blob),
        )
    else:
        fn = api.CryptUnprotectData
        fn.argtypes = [
            ctypes.POINTER(_DataBlob), ctypes.c_void_p,
            ctypes.POINTER(_DataBlob), ctypes.c_void_p, ctypes.c_void_p,
            wintypes.DWORD, ctypes.POINTER(_DataBlob),
        ]
        args = (
            ctypes.byref(input_blob), None, None, None, None,
            CRYPTPROTECT_UI_FORBIDDEN, ctypes.byref(output_blob),
        )
    fn.restype = wintypes.BOOL
    if not fn(*args):
        raise OSError(ctypes.get_last_error(), "Windows DPAPI operation failed")
    try:
        result = ctypes.string_at(output_blob.pbData, output_blob.cbData)
        if not result or len(result) > MAX_BLOB_BYTES:
            raise ValueError("Invalid Windows identity blob")
        return result
    finally:
        ctypes.WinDLL("kernel32", use_last_error=True).LocalFree(
            ctypes.cast(output_blob.pbData, ctypes.c_void_p)
        )


def _identity_path(directory: Path | None = None) -> Path:
    if os.name != "nt":
        raise OSError("Windows identity only supports Windows")
    if directory is None:
        local = os.environ.get("LOCALAPPDATA")
        if not local:
            raise OSError("Windows LOCALAPPDATA is unavailable")
        directory = Path(local) / "ChappyCompanion"
    if directory.is_symlink():
        raise OSError("Identity directory must not be a symlink")
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = directory / IDENTITY_FILENAME
    if path.is_symlink():
        raise OSError("Identity key file must not be a symlink")
    return path


def _fingerprint(key) -> str:
    from cryptography.hazmat.primitives import serialization

    public = key.public_key().public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return hashlib.sha256(public).hexdigest()


def _load_private(path: Path):
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec

    blob = path.read_bytes()
    if not 1 <= len(blob) <= MAX_BLOB_BYTES:
        raise ValueError("PC identity data is corrupt or too large")
    plain = _dpapi(blob, protect=False)
    if not plain.startswith(PLAINTEXT_PREFIX):
        raise ValueError("Unexpected PC identity format")
    key = serialization.load_der_private_key(
        plain[len(PLAINTEXT_PREFIX):], password=None
    )
    if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(
        key.curve, ec.SECP256R1
    ):
        raise ValueError("Only P-256 device identity is supported")
    return key


def identity_status(directory: Path | None = None) -> str | None:
    """Return the public SHA-256 fingerprint; never export the private key."""
    path = _identity_path(directory)
    if not path.exists():
        return None
    return _fingerprint(_load_private(path))


def create_identity(directory: Path | None = None) -> str:
    """Explicitly create ONCE. Existing data is never silently overwritten."""
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec

    path = _identity_path(directory)
    if path.exists():
        raise FileExistsError("PC identity already exists; revoke explicitly")
    key = ec.generate_private_key(ec.SECP256R1())
    raw = PLAINTEXT_PREFIX + key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    encrypted = _dpapi(raw, protect=True)
    # Exclusive create rejects concurrent or accidental overwrite. Windows
    # LOCALAPPDATA's user ACL protects the ciphertext as well as DPAPI.
    with path.open("xb") as output:
        output.write(encrypted)
        output.flush()
        os.fsync(output.fileno())
    return _fingerprint(key)


def revoke_identity(directory: Path | None = None) -> bool:
    """Local explicit invalidation: delete the only private signing key."""
    path = _identity_path(directory)
    if not path.exists():
        return False
    # Check first: fail closed on corrupted/unreadable state rather than
    # claiming a valid paired relationship was cleanly revoked.
    _load_private(path)
    path.unlink()
    return True

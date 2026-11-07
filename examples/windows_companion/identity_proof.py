"""Offline P-256 proof-of-possession primitives for future NETLAB-03B enrollment.

NO socket, pairing record, credential transfer, background task or PC command.
The caller must first authenticate the one-time TLS QR and obtain explicit
consent on both devices. An outstanding nonce must be consumed exactly once
by the future protocol; this module intentionally stores no session state.
"""
from __future__ import annotations

import base64
import binascii
import hashlib
import hmac
import re
import time
from pathlib import Path
from typing import Mapping

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

from windows_identity import _identity_path, _load_private

_VERSION = "CHAPPY-NETLAB-03B-PROOF-V1"
_HEX_16 = re.compile(r"[0-9a-f]{32}\Z")
_HEX_32 = re.compile(r"[0-9a-f]{64}\Z")
_MAX_EXPIRES_AT = 253402300799
_MAX_PROOF_AGE_SECONDS = 600


def _valid_hex(value: str, pattern: re.Pattern[str]) -> bool:
    return isinstance(value, str) and pattern.fullmatch(value) is not None


def canonical_challenge(
    *, role: str, invitation: str, tls_fingerprint: str,
    peer_fingerprint: str, nonce: str, expires_at: int,
) -> bytes:
    """Exact cross-platform UTF-8 bytes; no ambiguous separators or values."""
    if role not in ("pc", "android"):
        raise ValueError("Invalid proof signer role")
    if not _valid_hex(invitation, _HEX_16):
        raise ValueError("Invalid one-time invitation")
    for field in (tls_fingerprint, peer_fingerprint, nonce):
        if not _valid_hex(field, _HEX_32):
            raise ValueError("Expected lowercase 32-byte hex value")
    if type(expires_at) is not int or not 1 <= expires_at <= _MAX_EXPIRES_AT:
        raise ValueError("Invalid expiry")
    return (
        f"{_VERSION}\n"
        f"role={role}\n"
        f"invitation={invitation}\n"
        f"tls={tls_fingerprint}\n"
        f"peer={peer_fingerprint}\n"
        f"nonce={nonce}\n"
        f"expires={expires_at}\n"
    ).encode("ascii")


def _sign_with_key(
    private_key: ec.EllipticCurvePrivateKey, *, role: str,
    invitation: str, tls_fingerprint: str, peer_fingerprint: str,
    nonce: str, expires_at: int,
) -> dict[str, str]:
    """Testable signing core. Production PC key remains in local DPAPI."""
    if not isinstance(private_key.curve, ec.SECP256R1):
        raise ValueError("Only P-256 identity keys are supported")
    challenge = canonical_challenge(
        role=role, invitation=invitation, tls_fingerprint=tls_fingerprint,
        peer_fingerprint=peer_fingerprint, nonce=nonce, expires_at=expires_at,
    )
    spki = private_key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    signature = private_key.sign(challenge, ec.ECDSA(hashes.SHA256()))
    return {
        "algorithm": "P-256-SHA256",
        "spki": base64.b64encode(spki).decode("ascii"),
        "signature": base64.b64encode(signature).decode("ascii"),
    }


def sign_pc_challenge(
    *, invitation: str, tls_fingerprint: str, peer_fingerprint: str,
    nonce: str, expires_at: int, directory: Path | None = None,
) -> dict[str, str]:
    """Sign only an explicitly supplied enrollment challenge; never create a key."""
    # Not wired into the network listener or any mini-app/CLI endpoint.
    key = _load_private(_identity_path(directory))
    return _sign_with_key(
        key, role="pc", invitation=invitation,
        tls_fingerprint=tls_fingerprint, peer_fingerprint=peer_fingerprint,
        nonce=nonce, expires_at=expires_at,
    )


def _decode_canonical_base64(value: str, maximum: int) -> bytes:
    if not isinstance(value, str) or len(value) > 4 * ((maximum + 2) // 3):
        raise ValueError("Invalid proof field length")
    try:
        raw = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ValueError("Invalid base64") from exc
    if not 1 <= len(raw) <= maximum or base64.b64encode(raw).decode("ascii") != value:
        raise ValueError("Noncanonical proof field")
    return raw


def verify_identity_proof(
    response: Mapping[str, str], *, expected_signer_fingerprint: str,
    role: str, invitation: str, tls_fingerprint: str,
    peer_fingerprint: str, nonce: str, expires_at: int,
    now_epoch_seconds: int | None = None,
) -> bool:
    """Cryptographically check an *expected* public identity and exact context.

    The expected fingerprint MUST come from a separately authenticated channel,
    not from the response. A true pairing protocol must also track and consume
    each verifier-issued challenge nonce, require both user approvals, then
    store/revoke trusted peers. This function alone does NOT establish trust.
    """
    now = int(time.time()) if now_epoch_seconds is None else now_epoch_seconds
    if type(now) is not int or type(expires_at) is not int:
        return False
    if now > expires_at or expires_at - now > _MAX_PROOF_AGE_SECONDS:
        return False
    if not _valid_hex(expected_signer_fingerprint, _HEX_32):
        return False
    try:
        challenge = canonical_challenge(
            role=role, invitation=invitation, tls_fingerprint=tls_fingerprint,
            peer_fingerprint=peer_fingerprint, nonce=nonce, expires_at=expires_at,
        )
        if not isinstance(response, Mapping) or set(response) != {
            "algorithm", "spki", "signature",
        } or response["algorithm"] != "P-256-SHA256":
            return False
        spki = _decode_canonical_base64(response["spki"], 256)
        signature = _decode_canonical_base64(response["signature"], 256)
        if not hmac.compare_digest(
            hashlib.sha256(spki).hexdigest(), expected_signer_fingerprint,
        ):
            return False
        key = serialization.load_der_public_key(spki)
        if not isinstance(key, ec.EllipticCurvePublicKey) or not isinstance(
            key.curve, ec.SECP256R1
        ):
            return False
        key.verify(signature, challenge, ec.ECDSA(hashes.SHA256()))
        return True
    except (ValueError, TypeError, KeyError, InvalidSignature):
        return False

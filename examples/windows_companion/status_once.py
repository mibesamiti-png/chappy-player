"""Single-use, separately consented PC status read after a real QR-v3 proof.

Only used when the PC user explicitly selects --status-once. A matching
public fingerprint, QR alone, or the earlier two-sided identity verification
does NOT provide access. The Android key must sign a fresh, scope-separated
challenge, and the PC user separately types STATUS. No reusable token, files,
shell execution, automatic reconnect, or background monitoring.
"""
from __future__ import annotations

import hashlib
import hmac
import re
import secrets
import threading
import time
from collections.abc import Callable, Mapping

from identity_proof import sign_pc_challenge, verify_identity_proof
from pc_status_metrics import read_pc_status

PROTOCOL = "pc-status-once-v1"
SCOPE = "pc.status.read"
MAX_SECONDS = 90
HEX16 = re.compile(r"[0-9a-f]{32}\Z")
HEX32 = re.compile(r"[0-9a-f]{64}\Z")
METRIC_FIELDS = frozenset((
    "available", "logical_cpus", "memory_total_bytes",
    "memory_available_bytes", "uptime_seconds",
))


def scoped_nonce(raw: str) -> str:
    """Domain-separate status proofs from QR-v3 identity proofs.

    Underlying Android KeyStore/Windows DPAPI can keep using the existing
    canonical ECDSA proof format; nonce bytes change with the capability.
    """
    if not isinstance(raw, str) or HEX32.fullmatch(raw) is None:
        raise ValueError("Invalid status proof nonce")
    return hashlib.sha256(
        b"CHAPPY-PC-STATUS-READ-V1\x00" + bytes.fromhex(raw)
    ).hexdigest()


class StatusOnceAttempt:
    def __init__(
        self, *, identity, invitation: str, qr_expires: int,
        tls_fingerprint: str, pc_fingerprint: str,
        signer: Callable[..., dict[str, str]] = sign_pc_challenge,
        status_reader: Callable[[], dict[str, object]] = read_pc_status,
    ) -> None:
        if (not isinstance(invitation, str) or HEX16.fullmatch(invitation) is None
                or not isinstance(tls_fingerprint, str)
                or HEX32.fullmatch(tls_fingerprint) is None
                or not isinstance(pc_fingerprint, str)
                or HEX32.fullmatch(pc_fingerprint) is None
                or type(qr_expires) is not int or qr_expires < 1):
            raise ValueError("Invalid status-once bootstrap")
        self._identity = identity
        self._invitation = invitation
        self._qr_expires = qr_expires
        self._tls = tls_fingerprint
        self._pc_fp = pc_fingerprint
        self._sign = signer
        self._status_reader = status_reader
        self._lock = threading.Lock()
        self.finished = threading.Event()
        self._state = "new"
        self._phone_fp: str | None = None
        self._pc_nonce: str | None = None
        self._expires: int | None = None

    def begin(
        self, *, invitation: str, phone_fp: str, phone_nonce: str,
        approve_pc_status: Callable[[], bool],
    ) -> dict[str, object]:
        now = int(time.time())
        if (now >= self._qr_expires or not self._identity.finished.is_set()
                or not isinstance(invitation, str)
                or not hmac.compare_digest(invitation, self._invitation)
                or not isinstance(phone_fp, str)
                or HEX32.fullmatch(phone_fp) is None
                or not isinstance(phone_nonce, str)
                or HEX32.fullmatch(phone_nonce) is None):
            raise ValueError("Missing completed identity proof or expired invitation")
        verified_phone = self._identity.verified_phone_fingerprint
        if (verified_phone is None or
                not hmac.compare_digest(phone_fp, verified_phone)):
            raise PermissionError("Unverified phone key")
        with self._lock:
            if self._state != "new":
                raise PermissionError("Status request already consumed")
            # Consume the one-shot option before asking on the PC console.
            self._state = "pc_consent"
        try:
            if approve_pc_status() is not True:
                raise PermissionError("PC operator refused read-only status")
            now = int(time.time())
            if now >= self._qr_expires:
                raise ValueError("Status request expired")
            expires = min(now + MAX_SECONDS, self._qr_expires)
            pc_nonce = secrets.token_hex(32)
            pc_proof = self._sign(
                invitation=self._invitation, tls_fingerprint=self._tls,
                peer_fingerprint=phone_fp, nonce=scoped_nonce(phone_nonce),
                expires_at=expires,
            )
            if not verify_identity_proof(
                pc_proof, expected_signer_fingerprint=self._pc_fp,
                role="pc", invitation=self._invitation,
                tls_fingerprint=self._tls, peer_fingerprint=phone_fp,
                nonce=scoped_nonce(phone_nonce), expires_at=expires,
                now_epoch_seconds=now,
            ):
                raise ValueError("PC status signature mismatch")
            with self._lock:
                if self._state != "pc_consent":
                    raise PermissionError("Status already revoked")
                self._pc_nonce = pc_nonce
                self._phone_fp = phone_fp
                self._expires = expires
                self._state = "awaiting_phone_proof"
            return {
                "protocol": PROTOCOL, "status": "challenge",
                "pc_nonce": pc_nonce, "expires": expires,
                "pc_proof": pc_proof,
            }
        except BaseException:
            self.cancel()
            raise

    def finish(
        self, *, invitation: str, phone_fp: str,
        phone_proof: Mapping[str, str],
    ) -> dict[str, object]:
        with self._lock:
            if self._state != "awaiting_phone_proof":
                raise PermissionError("No status proof pending")
            self._state = "consumed"  # irreversible, including invalid proof
            expected_phone = self._phone_fp
            pc_nonce = self._pc_nonce
            expires = self._expires
        try:
            now = int(time.time())
            if (now >= expires or not isinstance(invitation, str)
                    or not hmac.compare_digest(invitation, self._invitation)
                    or not isinstance(phone_fp, str)
                    or not hmac.compare_digest(phone_fp, expected_phone)
                    or not self._identity.finished.is_set()
                    or self._identity.verified_phone_fingerprint is None
                    or not hmac.compare_digest(
                        phone_fp, self._identity.verified_phone_fingerprint)):
                raise ValueError("Wrong phone or expired status proof")
            if not verify_identity_proof(
                phone_proof, expected_signer_fingerprint=expected_phone,
                role="android", invitation=self._invitation,
                tls_fingerprint=self._tls, peer_fingerprint=self._pc_fp,
                nonce=scoped_nonce(pc_nonce), expires_at=expires,
                now_epoch_seconds=now,
            ):
                raise ValueError("Invalid independent status signature")
            # Only after real Android private-key proof AND both permissions.
            metrics = self._status_reader()
            if (type(metrics) is not dict or set(metrics) != METRIC_FIELDS or
                    type(metrics["available"]) is not bool):
                raise ValueError("Unsafe status provider")
            for field in METRIC_FIELDS - {"available"}:
                value = metrics[field]
                if value is not None and (type(value) is not int or value < 0):
                    raise ValueError("Unsafe status field")
            return {
                "protocol": PROTOCOL, "status": "ok",
                "pc_nonce": pc_nonce, "metrics": metrics,
            }
        finally:
            self.cancel()

    def cancel(self) -> None:
        with self._lock:
            self._state = "closed"
            self._phone_fp = None
            self._pc_nonce = None
            self._expires = None
            self.finished.set()

"""Single-use, separately consented PC traffic read after a real QR-v3 proof.

Only used when the PC user explicitly selects --traffic-read-once. A matching
public fingerprint, QR alone, or the earlier two-sided identity verification
does NOT provide access. The Android key must sign a fresh, scope-separated
challenge, and the PC user separately types TRAFFIC. No reusable token, files,
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
from pc_traffic_export import capture, MAX_BYTES

PROTOCOL = "pc-traffic-once-v1"
SCOPE = "pc.traffic.read"
MAX_SECONDS = 90
HEX16 = re.compile(r"[0-9a-f]{32}\Z")
HEX32 = re.compile(r"[0-9a-f]{64}\Z")
REPORT_FIELDS = frozenset(("format", "source", "coverage", "interval_ms", "samples", "totals"))


def scoped_nonce(raw: str, seconds: int) -> str:
    """Domain-separate traffic proofs from QR-v3 identity proofs.

    Underlying Android KeyStore/Windows DPAPI can keep using the existing
    canonical ECDSA proof format; nonce bytes change with the capability.
    """
    if type(seconds) is not int or not 5 <= seconds <= 30:
        raise ValueError('Invalid traffic duration')
    if not isinstance(raw, str) or HEX32.fullmatch(raw) is None:
        raise ValueError("Invalid traffic proof nonce")
    return hashlib.sha256(
        b"CHAPPY-PC-TRAFFIC-READ-V1\x00" + bytes([seconds]) + bytes.fromhex(raw)
    ).hexdigest()


class TrafficOnceAttempt:
    def __init__(
        self, *, identity, invitation: str, qr_expires: int,
        tls_fingerprint: str, pc_fingerprint: str,
        signer: Callable[..., dict[str, str]] = sign_pc_challenge,
        traffic_reader: Callable[[int], dict[str, object]] = lambda seconds: capture(samples=seconds),
        seconds: int = 10,
    ) -> None:
        if (not isinstance(invitation, str) or HEX16.fullmatch(invitation) is None
                or not isinstance(tls_fingerprint, str)
                or HEX32.fullmatch(tls_fingerprint) is None
                or not isinstance(pc_fingerprint, str)
                or HEX32.fullmatch(pc_fingerprint) is None
                or type(qr_expires) is not int or qr_expires < 1):
            raise ValueError("Invalid traffic-once bootstrap")
        if type(seconds) is not int or not 5 <= seconds <= 30:
            raise ValueError('Invalid traffic duration')
        self.seconds = seconds
        self._identity = identity
        self._invitation = invitation
        self._qr_expires = qr_expires
        self._tls = tls_fingerprint
        self._pc_fp = pc_fingerprint
        self._sign = signer
        self._traffic_reader = traffic_reader
        self._lock = threading.Lock()
        self.finished = threading.Event()
        self._state = "new"
        self._phone_fp: str | None = None
        self._pc_nonce: str | None = None
        self._expires: int | None = None

    def begin(
        self, *, invitation: str, phone_fp: str, phone_nonce: str,
        approve_pc_traffic: Callable[[], bool],
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
                raise PermissionError("Traffic request already consumed")
            # Consume the one-shot option before asking on the PC console.
            self._state = "pc_consent"
        try:
            if approve_pc_traffic() is not True:
                raise PermissionError("PC operator refused read-only traffic")
            now = int(time.time())
            if now >= self._qr_expires:
                raise ValueError("Traffic request expired")
            expires = min(now + MAX_SECONDS, self._qr_expires)
            pc_nonce = secrets.token_hex(32)
            pc_proof = self._sign(
                invitation=self._invitation, tls_fingerprint=self._tls,
                peer_fingerprint=phone_fp, nonce=scoped_nonce(phone_nonce, self.seconds),
                expires_at=expires,
            )
            if not verify_identity_proof(
                pc_proof, expected_signer_fingerprint=self._pc_fp,
                role="pc", invitation=self._invitation,
                tls_fingerprint=self._tls, peer_fingerprint=phone_fp,
                nonce=scoped_nonce(phone_nonce, self.seconds), expires_at=expires,
                now_epoch_seconds=now,
            ):
                raise ValueError("PC traffic signature mismatch")
            with self._lock:
                if self._state != "pc_consent":
                    raise PermissionError("Traffic already revoked")
                self._pc_nonce = pc_nonce
                self._phone_fp = phone_fp
                self._expires = expires
                self._state = "awaiting_phone_proof"
            return {
                "protocol": PROTOCOL, "status": "challenge",
                "pc_nonce": pc_nonce, "expires": expires,
                "pc_proof": pc_proof, "seconds": self.seconds,
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
                raise PermissionError("No traffic proof pending")
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
                raise ValueError("Wrong phone or expired traffic proof")
            if not verify_identity_proof(
                phone_proof, expected_signer_fingerprint=expected_phone,
                role="android", invitation=self._invitation,
                tls_fingerprint=self._tls, peer_fingerprint=self._pc_fp,
                nonce=scoped_nonce(pc_nonce, self.seconds), expires_at=expires,
                now_epoch_seconds=now,
            ):
                raise ValueError("Invalid independent traffic signature")
            # Only after real Android private-key proof AND both permissions.
            # Capture only this PC's all-interface byte COUNTERS after proof.
            report = self._traffic_reader(self.seconds)
            self._validate_report(report)
            if len(report["samples"]) != self.seconds:
                raise ValueError("Unexpected capture duration")
            if self.finished.is_set() or int(time.time()) >= expires:
                raise PermissionError("Traffic request expired or cancelled")
            return {
                "protocol": PROTOCOL, "status": "ok",
                "pc_nonce": pc_nonce, "report": report,
            }
        finally:
            self.cancel()

    @staticmethod
    def _validate_report(report: object) -> None:
        import json
        if type(report) is not dict or set(report) != REPORT_FIELDS or (
            report["format"] != "chappy.remote-traffic.v1"
            or report["source"] != "windows_pc"
            or report["coverage"] != "all_interfaces"
            or report["interval_ms"] != 1000
        ):
            raise ValueError("Unsafe traffic report")
        samples = report["samples"]
        totals = report["totals"]
        if type(samples) is not list or not 5 <= len(samples) <= 30 or (
            type(totals) is not dict or set(totals) != {"rx_bytes", "tx_bytes"}
        ):
            raise ValueError("Unsafe samples or totals")
        rx = tx = 0
        for point in samples:
            if type(point) is not dict or set(point) != {"rx_bytes", "tx_bytes"}:
                raise ValueError("Report contained identifiers")
            if any(type(v) is not int or not 0 <= v <= MAX_BYTES
                   for v in point.values()):
                raise ValueError("Bad traffic counter")
            rx += point["rx_bytes"]
            tx += point["tx_bytes"]
        if rx > MAX_BYTES or tx > MAX_BYTES or totals != {
            "rx_bytes": rx, "tx_bytes": tx,
        }:
            raise ValueError("Traffic totals mismatch")
        if len(json.dumps(report, separators=(",", ":")).encode()) > 16 * 1024:
            raise ValueError("Traffic report too large")

    def cancel(self) -> None:
        with self._lock:
            self._state = "closed"
            self._phone_fp = None
            self._pc_nonce = None
            self._expires = None
            self.finished.set()

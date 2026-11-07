"""Bounded, single-use mutual proof gate for *future* QR-pinned enrollment.

This is deliberately offline. No listener, JS bridge, persistent enrollment,
background task or authority to read/control the PC. The caller must authenticate
the displayed QR/TLS pin AND independently confirm both public device identities
and both people's on-screen decisions before using this as a pairing component.
"""
from __future__ import annotations

from dataclasses import dataclass
import secrets
import threading
import time

from identity_proof import canonical_challenge, verify_identity_proof

MAX_SECONDS = 600


@dataclass(frozen=True)
class ProofRequest:
    role: str
    invitation: str
    tls_fingerprint: str
    peer_fingerprint: str
    nonce: str
    expires_at: int


class MutualProofSession:
    """Fail-closed, one-shot state machine. No connection or trust is persisted.

    Per direction: the PC verifies an Android signature on the PC-issued nonce;
    Android verifies a PC signature on the phone-issued nonce. The verifier must
    deliver its own nonce across an already authenticated, pinned-TLS connection.
    """

    def __init__(
        self, *, invitation: str, tls_fingerprint: str,
        pc_fingerprint: str, android_fingerprint: str,
        expires_at: int, now_epoch_seconds: int | None = None,
        phone_issued_nonce: str | None = None,
    ) -> None:
        now = int(time.time()) if now_epoch_seconds is None else now_epoch_seconds
        if type(now) is not int or type(expires_at) is not int or not (
            0 < expires_at - now <= MAX_SECONDS
        ):
            raise ValueError("The enrollment must have a short future expiry")
        if pc_fingerprint == android_fingerprint:
            raise ValueError("The two device identities must be distinct")
        # Reuse the strict cross-platform input validator.
        for role, peer in (
            ("android", pc_fingerprint), ("pc", android_fingerprint)
        ):
            canonical_challenge(
                role=role, invitation=invitation, tls_fingerprint=tls_fingerprint,
                peer_fingerprint=peer, nonce="0" * 64, expires_at=expires_at,
            )
        self._pc_request = ProofRequest(
            role="android", invitation=invitation,
            tls_fingerprint=tls_fingerprint, peer_fingerprint=pc_fingerprint,
            nonce=secrets.token_hex(32), expires_at=expires_at,
        )
        # The actual Android verifier issues its own nonce; the PC may not
        # silently replace it with a nonce of its choosing.
        if phone_issued_nonce is not None:
            canonical_challenge(
                role="pc", invitation=invitation,
                tls_fingerprint=tls_fingerprint,
                peer_fingerprint=android_fingerprint,
                nonce=phone_issued_nonce, expires_at=expires_at,
            )
            if phone_issued_nonce == self._pc_request.nonce:
                raise ValueError("Verifier nonces must be distinct")
        self._phone_request = ProofRequest(
            role="pc", invitation=invitation,
            tls_fingerprint=tls_fingerprint, peer_fingerprint=android_fingerprint,
            nonce=phone_issued_nonce if phone_issued_nonce is not None
                else secrets.token_hex(32), expires_at=expires_at,
        )
        self._pc_fingerprint = pc_fingerprint
        self._android_fingerprint = android_fingerprint
        self._expires_at = expires_at
        self._lock = threading.Lock()
        self._pc_verified = False
        self._phone_verified = False
        self._pc_approved = False
        self._phone_approved = False
        self._closed = False

    @property
    def pc_issued_request_for_android(self) -> ProofRequest:
        return self._pc_request

    @property
    def android_issued_request_for_pc(self) -> ProofRequest:
        return self._phone_request

    def _active(self, now: int) -> bool:
        if type(now) is not int or now >= self._expires_at:
            self._closed = True
        return not self._closed

    def submit_proof(
        self, *, signer: str, response: dict[str, str],
        now_epoch_seconds: int | None = None,
    ) -> bool:
        """Consume exactly one attempt per signer. Invalid proof closes session.

        In real networking, the requester must own its nonce; this state machine
        does not replace channel binding, the phone-side verifier, or user consent.
        """
        now = int(time.time()) if now_epoch_seconds is None else now_epoch_seconds
        with self._lock:
            if not self._active(now):
                return False
            if signer == "android" and not self._pc_verified:
                req = self._pc_request
                fp = self._android_fingerprint
            elif signer == "pc" and not self._phone_verified:
                req = self._phone_request
                fp = self._pc_fingerprint
            else:
                self._closed = True  # invalid/duplicate/reflection attempt
                return False
            valid = verify_identity_proof(
                response, expected_signer_fingerprint=fp,
                role=req.role, invitation=req.invitation,
                tls_fingerprint=req.tls_fingerprint,
                peer_fingerprint=req.peer_fingerprint,
                nonce=req.nonce, expires_at=req.expires_at,
                now_epoch_seconds=now,
            )
            if not valid:
                self._closed = True
                return False
            if signer == "android":
                self._pc_verified = True
            else:
                self._phone_verified = True
            return True

    def approve(
        self, *, side: str, approved: bool,
        now_epoch_seconds: int | None = None,
    ) -> bool:
        """Record an independent and explicit UI decision on the indicated side."""
        now = int(time.time()) if now_epoch_seconds is None else now_epoch_seconds
        with self._lock:
            if not self._active(now):
                return False
            if not isinstance(approved, bool) or not approved or not (
                self._pc_verified and self._phone_verified
            ):
                self._closed = True
                return False
            if side == "pc" and not self._pc_approved:
                self._pc_approved = True
            elif side == "android" and not self._phone_approved:
                self._phone_approved = True
            else:
                self._closed = True
                return False
            return True

    def complete(self, *, now_epoch_seconds: int | None = None) -> bool:
        """Return one-time confirmation; never create a trusted peer record."""
        now = int(time.time()) if now_epoch_seconds is None else now_epoch_seconds
        with self._lock:
            if not self._active(now):
                return False
            approved = (
                self._pc_verified and self._phone_verified
                and self._pc_approved and self._phone_approved
            )
            # A premature completion attempt must not be retried as success.
            self._closed = True
            return bool(approved)

    def cancel(self) -> None:
        """Stop on network change, app pause, timeout or user cancellation."""
        with self._lock:
            self._closed = True

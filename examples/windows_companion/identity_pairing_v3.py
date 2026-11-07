"""Single-use, user-confirmed QR-v3 identity challenge state machine.

Network wiring is in pairing_server.py. This session does not save trusted
devices, grant privileges, start listeners or expose remote commands.
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

_HEX16 = re.compile(r"[0-9a-f]{32}\Z")
_HEX32 = re.compile(r"[0-9a-f]{64}\Z")
PROTOCOL = "pair-identity-v3"
MAX_FINALIZE_SECONDS = 90


def _hex(value: object, pattern: re.Pattern[str]) -> bool:
    return isinstance(value, str) and pattern.fullmatch(value) is not None


def comparison_code(phone_nonce: str) -> str:
    """Human check code for this session, not an authentication secret."""
    if not _hex(phone_nonce, _HEX32):
        raise ValueError("Expected 32-byte phone nonce")
    return hashlib.sha256(bytes.fromhex(phone_nonce)).hexdigest()[:6].upper()


class IdentityPairingAttempt:
    """One QR claim -> one approved PC proof -> one phone proof -> terminal.

    All identity claims and TLS pins must originate from a user-scanned QR.
    No retry of either phase after an error. A caller must ensure the network
    is a pinned TLS private LAN endpoint and the Android user has approved.
    """

    def __init__(
        self, *, invitation: str, qr_expires: int, tls_fingerprint: str,
        pc_fingerprint: str,
        signer: Callable[..., dict[str, str]] = sign_pc_challenge,
        expected_phone_fingerprint: str | None = None,
    ) -> None:
        if not _hex(invitation, _HEX16) or not all(
            _hex(item, _HEX32) for item in (tls_fingerprint, pc_fingerprint)
        ) or type(qr_expires) is not int or qr_expires <= 0:
            raise ValueError("Invalid identity session bootstrap")
        if (expected_phone_fingerprint is not None and not _hex(
            expected_phone_fingerprint, _HEX32
        )):
            raise ValueError("Invalid manually selected phone fingerprint")
        self.expected_phone_fingerprint = expected_phone_fingerprint
        self.invitation = invitation
        self.qr_expires = qr_expires
        self.tls_fingerprint = tls_fingerprint
        self.pc_fingerprint = pc_fingerprint
        self.signer = signer
        self.finished = threading.Event()
        self._lock = threading.Lock()
        self._state = "new"
        self._phone_fingerprint = None
        self._phone_nonce = None
        self._pc_nonce = None
        self._proof_expires = None
        # Set only after an authenticated Android proof, never on begin/denial.
        self._verified_phone = None

    @property
    def verified_phone_fingerprint(self) -> str | None:
        # The result is informational and cannot authorize later connections.
        with self._lock:
            return self._verified_phone if self.finished.is_set() else None

    def _expired(self, now: int) -> bool:
        return now >= self.qr_expires

    def begin(
        self, *, invitation: str, phone_fingerprint: str, phone_nonce: str,
        approve_on_pc: Callable[[str], bool],
    ) -> dict[str, object]:
        now = int(time.time())
        if not _hex(invitation, _HEX16) or not hmac.compare_digest(
            invitation, self.invitation
        ) or not _hex(phone_fingerprint, _HEX32) or not _hex(
            phone_nonce, _HEX32
        ) or self._expired(now):
            raise ValueError("Invalid or expired identity invitation")
        # A caller-chosen, previously verified key is an EXPECTATION, not
        # an authorization. Reject a different phone claim BEFORE prompting
        # the PC operator, claiming the QR invite, or signing any challenge.
        # A matching claim still must prove P-256 key possession at finish.
        if self.expected_phone_fingerprint is not None and not hmac.compare_digest(
            phone_fingerprint, self.expected_phone_fingerprint
        ):
            raise ValueError("Phone public fingerprint differs from chosen history")
        with self._lock:
            if self._state != "new":
                raise ValueError("Identity invitation already claimed")
            self._state = "pending_pc_approval"
            self._phone_fingerprint = phone_fingerprint
            self._phone_nonce = phone_nonce
        try:
            # The PC must show the phone's public identity and check the code.
            # Successful PC approval is needed BEFORE touching the private key.
            if not approve_on_pc(phone_nonce):
                raise PermissionError("User denied identity enrollment")
            now = int(time.time())
            if self._expired(now):
                raise ValueError("Identity invitation expired")
            expires = min(self.qr_expires, now + MAX_FINALIZE_SECONDS)
            pc_nonce = secrets.token_hex(32)
            proof = self.signer(
                invitation=self.invitation,
                tls_fingerprint=self.tls_fingerprint,
                peer_fingerprint=phone_fingerprint,
                nonce=phone_nonce,
                expires_at=expires,
            )
            # Fail closed if an absent/replaced PC key signs a different identity.
            if not verify_identity_proof(
                proof, expected_signer_fingerprint=self.pc_fingerprint,
                role="pc", invitation=self.invitation,
                tls_fingerprint=self.tls_fingerprint,
                peer_fingerprint=phone_fingerprint, nonce=phone_nonce,
                expires_at=expires, now_epoch_seconds=now,
            ):
                raise ValueError("Unexpected PC identity signature")
            with self._lock:
                if self._state != "pending_pc_approval":
                    raise ValueError("Identity confirmation cancelled")
                self._state = "awaiting_phone_proof"
                self._pc_nonce = pc_nonce
                self._proof_expires = expires
            return {
                "status": "challenge", "protocol": PROTOCOL,
                "phone_nonce": phone_nonce, "pc_nonce": pc_nonce,
                "expires": expires, "pc_proof": proof,
            }
        except BaseException:
            with self._lock:
                self._state = "failed"
                self.finished.set()
            raise

    def finish(
        self, *, invitation: str, phone_fingerprint: str,
        phone_proof: Mapping[str, str],
    ) -> dict[str, object]:
        # State is irreversibly consumed before costly signature verification.
        with self._lock:
            if self._state != "awaiting_phone_proof":
                raise ValueError("No pending proof or challenge already consumed")
            self._state = "consumed"
            fp = self._phone_fingerprint
            phone_nonce = self._phone_nonce
            pc_nonce = self._pc_nonce
            expires = self._proof_expires
        try:
            now = int(time.time())
            if (
                not _hex(invitation, _HEX16)
                or not hmac.compare_digest(invitation, self.invitation)
                or not _hex(phone_fingerprint, _HEX32)
                or not hmac.compare_digest(phone_fingerprint, fp)
                or now >= expires
            ):
                raise ValueError("Invalid or expired phone proof")
            if not verify_identity_proof(
                phone_proof, expected_signer_fingerprint=fp,
                role="android", invitation=self.invitation,
                tls_fingerprint=self.tls_fingerprint,
                peer_fingerprint=self.pc_fingerprint, nonce=pc_nonce,
                expires_at=expires, now_epoch_seconds=now,
            ):
                raise ValueError("Phone failed identity proof")
            with self._lock:
                self._verified_phone = fp
            return {
                "status": "approved", "protocol": PROTOCOL,
                "phone_nonce": phone_nonce, "pc_nonce": pc_nonce,
            }
        finally:
            with self._lock:
                self._state = "complete"
                self.finished.set()

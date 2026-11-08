"""Offline-only PC Link R4B session/capability model; no transport and no credentials.

This cannot be used to grant production PC access. Real binding of QR-v3 proof,
a pinned TLS channel, two new user consents and the authenticated peer must be
implemented and verified separately before any network endpoint is enabled.
"""
from __future__ import annotations

import threading
from collections.abc import Mapping

PROTOCOL = "pc-link-session-preview-v1"
STATUS_CAPABILITY = "pc.status.read"
MAX_LIFETIME_SECONDS = 120
REQUEST_FIELDS = frozenset(("protocol", "kind", "sequence", "capability"))
RESPONSE_FIELDS = REQUEST_FIELDS | frozenset(("online",))


class OfflinePreviewSession:
    """One-use, bounded consent gate. No file read, socket or saved key.

    Caller-supplied identity_verified is *only* a test input for a future
    authenticated integration. This offline model is NOT a network authenticator.
    """

    def __init__(self, *, now_epoch_seconds: int, expires_at: int) -> None:
        if (type(now_epoch_seconds) is not int or type(expires_at) is not int
                or not 0 < expires_at - now_epoch_seconds <= MAX_LIFETIME_SECONDS):
            raise ValueError("Invalid short session lifetime")
        self._lock = threading.RLock()
        self._expires_at = expires_at
        self._phase = "new"
        self._scope = None
        self._pc_consent = False
        self._phone_consent = False
        self._last_sequence = 0

    def _alive(self, now: int) -> bool:
        if type(now) is not int or now >= self._expires_at:
            self._phase = "closed"
        return self._phase != "closed"

    def phase(self, *, now_epoch_seconds: int) -> str:
        with self._lock:
            self._alive(now_epoch_seconds)
            return self._phase

    def verify(self, *, identity_verified: bool, now_epoch_seconds: int) -> bool:
        with self._lock:
            if not self._alive(now_epoch_seconds) or self._phase != "new":
                self._phase = "closed"
                return False
            if identity_verified is not True:
                self._phase = "closed"
                return False
            # QR-v3 identity success itself NEVER grants a capability.
            self._phase = "verified"
            return True

    def request_read_only(self, *, capability: str, now_epoch_seconds: int) -> bool:
        with self._lock:
            if (not self._alive(now_epoch_seconds) or self._phase != "verified"
                    or capability != STATUS_CAPABILITY):
                self._phase = "closed"
                return False
            self._phase = "awaiting_consent"
            self._scope = capability
            return True

    def consent(
        self, *, side: str, approved: bool, now_epoch_seconds: int
    ) -> bool:
        with self._lock:
            if (not self._alive(now_epoch_seconds)
                    or self._phase != "awaiting_consent"
                    or side not in ("pc", "android")
                    or approved is not True):
                self._phase = "closed"
                return False
            if side == "pc" and not self._pc_consent:
                self._pc_consent = True
            elif side == "android" and not self._phone_consent:
                self._phone_consent = True
            else:
                self._phase = "closed"  # replay / repeated consent
                return False
            if self._pc_consent and self._phone_consent:
                self._phase = "active"
            return True

    def allows(self, *, capability: str, now_epoch_seconds: int) -> bool:
        with self._lock:
            return (self._alive(now_epoch_seconds)
                    and self._phase == "active"
                    and capability == self._scope == STATUS_CAPABILITY)

    def accept_fixture_request(
        self, message: Mapping[str, object], *, now_epoch_seconds: int
    ) -> dict[str, object] | None:
        """Validate deterministic test-only message; never fetch PC information."""
        with self._lock:
            if not self._alive(now_epoch_seconds) or self._phase != "active":
                return None
            if (not isinstance(message, Mapping)
                    or set(message) != REQUEST_FIELDS
                    or message.get("protocol") != PROTOCOL
                    or message.get("kind") != "status-request"
                    or message.get("capability") != STATUS_CAPABILITY
                    or type(message.get("sequence")) is not int
                    or not self._last_sequence < message["sequence"] <= 1000):
                self._phase = "closed"
                return None
            self._last_sequence = message["sequence"]
            # Simulated fixture only. Never claim real PC online/state metrics.
            return {
                "protocol": PROTOCOL, "kind": "status-fixture",
                "sequence": self._last_sequence,
                "capability": STATUS_CAPABILITY, "online": True,
            }

    def cancel(self) -> None:
        with self._lock:
            self._phase = "closed"
            self._scope = None
            self._pc_consent = self._phone_consent = False


def validate_fixture_response(
    message: Mapping[str, object], *, sequence: int
) -> bool:
    """Strict cross-platform fixture parser; no arbitrary extra data accepted."""
    return (
        isinstance(message, Mapping)
        and set(message) == RESPONSE_FIELDS
        and message.get("protocol") == PROTOCOL
        and message.get("kind") == "status-fixture"
        and message.get("capability") == STATUS_CAPABILITY
        and type(sequence) is int and 1 <= sequence <= 1000
        and type(message.get("sequence")) is int
        and message.get("sequence") == sequence
        and type(message.get("online")) is bool
    )

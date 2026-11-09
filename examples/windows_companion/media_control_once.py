"""One Windows multimedia key only after an independently approved QR-v3 proof."""
from __future__ import annotations
import hashlib
import hmac
import os
import re
import secrets
import threading
import time
from collections.abc import Callable, Mapping
from identity_proof import sign_pc_challenge, verify_identity_proof

PROTOCOL = "pc-media-once-v1"
SCOPE = "pc.media.control"
MAX_SECONDS = 90
COMMAND_KEYS = {"volume_up": 0xAF, "volume_down": 0xAE,
                "toggle_mute": 0xAD, "play_pause": 0xB3}
HEX16 = re.compile(r"[0-9a-f]{32}\Z")
HEX32 = re.compile(r"[0-9a-f]{64}\Z")


def scoped_nonce(raw: str, command: str) -> str:
    if (type(raw) is not str or HEX32.fullmatch(raw) is None
            or type(command) is not str or command not in COMMAND_KEYS):
        raise ValueError("Invalid media scope or nonce")
    return hashlib.sha256(
        b"CHAPPY-PC-MEDIA-CONTROL-V1\x00" + command.encode("ascii")
        + b"\x00" + bytes.fromhex(raw)
    ).hexdigest()


def execute_windows_media_key(command: str) -> None:
    """Only four fixed multimedia virtual keys; NO arbitrary keyboard input."""
    if type(command) is not str or command not in COMMAND_KEYS:
        raise ValueError("Unsupported media command")
    if os.name != "nt":
        raise OSError("Windows only")
    import ctypes
    vk = COMMAND_KEYS[command]
    user32 = ctypes.windll.user32
    user32.keybd_event(vk, 0, 0, 0)
    user32.keybd_event(vk, 0, 2, 0)


class MediaOnceAttempt:
    def __init__(
        self, *, identity, invitation: str, qr_expires: int,
        tls_fingerprint: str, pc_fingerprint: str,
        signer: Callable[..., dict[str, str]] = sign_pc_challenge,
        executor: Callable[[str], None] = execute_windows_media_key,
    ) -> None:
        if (type(invitation) is not str or HEX16.fullmatch(invitation) is None
                or type(tls_fingerprint) is not str
                or HEX32.fullmatch(tls_fingerprint) is None
                or type(pc_fingerprint) is not str
                or HEX32.fullmatch(pc_fingerprint) is None
                or type(qr_expires) is not int or qr_expires < 1):
            raise ValueError("Invalid media bootstrap")
        self._identity = identity
        self._invitation = invitation
        self._qr_expires = qr_expires
        self._tls = tls_fingerprint
        self._pc_fp = pc_fingerprint
        self._sign = signer
        self._execute = executor
        self._lock = threading.Lock()
        self.finished = threading.Event()
        self._state = "new"
        self._command: str | None = None
        self._phone_fp: str | None = None
        self._pc_nonce: str | None = None
        self._expires: int | None = None

    def begin(
        self, *, invitation: str, phone_fp: str, phone_nonce: str,
        command: str, approve_pc_media: Callable[[str], bool],
    ) -> dict[str, object]:
        now = int(time.time())
        if (now >= self._qr_expires or not self._identity.finished.is_set()
                or type(invitation) is not str
                or not hmac.compare_digest(invitation, self._invitation)
                or type(phone_fp) is not str or HEX32.fullmatch(phone_fp) is None
                or type(phone_nonce) is not str or HEX32.fullmatch(phone_nonce) is None
                or type(command) is not str or command not in COMMAND_KEYS):
            raise ValueError("Unverified identity or invalid media request")
        trusted = self._identity.verified_phone_fingerprint
        if trusted is None or not hmac.compare_digest(phone_fp, trusted):
            raise PermissionError("Unverified Android key")
        with self._lock:
            if self._state != "new":
                raise PermissionError("Media request already consumed")
            self._state = "pc_consent"
        try:
            if approve_pc_media(command) is not True:
                raise PermissionError("PC user refused media command")
            now = int(time.time())
            if now >= self._qr_expires:
                raise ValueError("Expired media QR")
            expires = min(now + MAX_SECONDS, self._qr_expires)
            pc_nonce = secrets.token_hex(32)
            bound = scoped_nonce(phone_nonce, command)
            proof = self._sign(
                invitation=self._invitation, tls_fingerprint=self._tls,
                peer_fingerprint=phone_fp, nonce=bound, expires_at=expires,
            )
            if not verify_identity_proof(
                proof, expected_signer_fingerprint=self._pc_fp,
                role="pc", invitation=self._invitation,
                tls_fingerprint=self._tls, peer_fingerprint=phone_fp,
                nonce=bound, expires_at=expires, now_epoch_seconds=now,
            ):
                raise ValueError("Invalid Windows media proof")
            with self._lock:
                if self._state != "pc_consent":
                    raise PermissionError("Media capability revoked")
                self._command = command
                self._phone_fp = phone_fp
                self._pc_nonce = pc_nonce
                self._expires = expires
                self._state = "awaiting_phone"
            return {"protocol": PROTOCOL, "status": "challenge",
                    "command": command, "pc_nonce": pc_nonce,
                    "expires": expires, "pc_proof": proof}
        except BaseException:
            self.cancel()
            raise

    def finish(
        self, *, invitation: str, phone_fp: str,
        phone_proof: Mapping[str, str],
    ) -> dict[str, object]:
        with self._lock:
            if self._state != "awaiting_phone":
                raise PermissionError("No media proof pending")
            self._state = "consumed"
            command = self._command
            expected_phone = self._phone_fp
            pc_nonce = self._pc_nonce
            expires = self._expires
        try:
            now = int(time.time())
            trusted = self._identity.verified_phone_fingerprint
            if (not self._identity.finished.is_set() or now >= expires
                    or type(invitation) is not str
                    or not hmac.compare_digest(invitation, self._invitation)
                    or type(phone_fp) is not str
                    or not hmac.compare_digest(phone_fp, expected_phone)
                    or trusted is None
                    or not hmac.compare_digest(phone_fp, trusted)):
                raise ValueError("Expired, mismatched or revoked media request")
            if not verify_identity_proof(
                phone_proof, expected_signer_fingerprint=expected_phone,
                role="android", invitation=self._invitation,
                tls_fingerprint=self._tls, peer_fingerprint=self._pc_fp,
                nonce=scoped_nonce(pc_nonce, command),
                expires_at=expires, now_epoch_seconds=now,
            ):
                raise ValueError("Android proof not bound to requested action")
            self._execute(command)
            return {"protocol": PROTOCOL, "status": "executed",
                    "pc_nonce": pc_nonce, "command": command}
        finally:
            self.cancel()

    def cancel(self) -> None:
        with self._lock:
            self._state = "closed"
            self._command = self._phone_fp = self._pc_nonce = self._expires = None
            self.finished.set()

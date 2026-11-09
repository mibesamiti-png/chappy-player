"""R5A: one PC-owner-selected file -> authenticated Android, never arbitrary paths.

Not a general file server. A local PC user selects exactly one regular file
BEFORE the listener starts; only its bounded bytes and safe display name enter
RAM. QR-v3 mutual identity is required; an additional PC SEND approval and a
new Android KeyStore P-256 signature in the pc.file.receive scope are required.

Chunk ticket is short-lived, random, one-session, strictly sequential, and
works ONLY over the original QR-pinned TLS listener. No credentials persist.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import re
import secrets
import threading
import time
from collections.abc import Callable, Mapping
from pathlib import Path

from identity_proof import sign_pc_challenge, verify_identity_proof

PROTOCOL = "pc-file-receive-v1"
SCOPE = "pc.file.receive"
MAX_FILE_BYTES = 4 * 1024 * 1024
CHUNK_BYTES = 16 * 1024
MAX_SESSION_SECONDS = 240
_HEX16 = re.compile(r"[0-9a-f]{32}\Z")
_HEX32 = re.compile(r"[0-9a-f]{64}\Z")
_FORBIDDEN_NAME = re.compile(r'[/\\:*?"<>|\x00-\x1f\x7f]')


def safe_name(value: str) -> str:
    if (not isinstance(value, str) or not 1 <= len(value) <= 96
            or value in (".", "..") or value.endswith((" ", "."))
            or _FORBIDDEN_NAME.search(value) is not None
            or len(value.encode("utf-8")) > 180):
        raise ValueError("Unsafe selected filename")
    return value


def scoped_nonce(raw_hex: str) -> str:
    if not isinstance(raw_hex, str) or _HEX32.fullmatch(raw_hex) is None:
        raise ValueError("Expected 32-byte independent transfer nonce")
    return hashlib.sha256(
        b"CHAPPY-PC-FILE-RECEIVE-V1\x00" + bytes.fromhex(raw_hex)
    ).hexdigest()


class SelectedFile:
    """Immutable snapshot of a local file chosen by the PC owner."""

    def __init__(self, *, name: str, content: bytes) -> None:
        self.name = safe_name(name)
        if type(content) is not bytes or not 1 <= len(content) <= MAX_FILE_BYTES:
            raise ValueError("File must contain 1 byte to 4 MiB")
        self.content = content
        self.size = len(content)
        self.sha256 = hashlib.sha256(content).hexdigest()

    @classmethod
    def from_local_selection(cls, path_text: str) -> "SelectedFile":
        if not isinstance(path_text, str) or not path_text.strip():
            raise ValueError("No file explicitly selected")
        path = Path(path_text.strip().strip('"')).expanduser()
        # No remote path parameter; no directory, symbolic link or UNC share.
        if (str(path).startswith(("\\\\", "//")) or
                not path.is_absolute() or path.is_symlink() or not path.is_file()):
            raise ValueError("Select one regular local file, not a link or directory")
        size = path.stat().st_size
        if not 1 <= size <= MAX_FILE_BYTES:
            raise ValueError("The preview supports 1 byte to 4 MiB")
        content = path.read_bytes()
        if len(content) != size:
            raise ValueError("Selected file changed during read")
        return cls(name=path.name, content=content)


class FileSendOnceAttempt:
    def __init__(
        self, *, identity, invitation: str, qr_expires: int,
        tls_fingerprint: str, pc_fingerprint: str, selected: SelectedFile,
        signer: Callable[..., dict[str, str]] = sign_pc_challenge,
    ) -> None:
        if (not isinstance(invitation, str) or _HEX16.fullmatch(invitation) is None
                or not isinstance(tls_fingerprint, str)
                or _HEX32.fullmatch(tls_fingerprint) is None
                or not isinstance(pc_fingerprint, str)
                or _HEX32.fullmatch(pc_fingerprint) is None
                or type(qr_expires) is not int or qr_expires < 1
                or not isinstance(selected, SelectedFile)):
            raise ValueError("Invalid file sender bootstrap")
        self.identity = identity
        self.invitation = invitation
        self.qr_expires = qr_expires
        self.tls = tls_fingerprint
        self.pc_fp = pc_fingerprint
        self.selected = selected
        self.signer = signer
        self._lock = threading.RLock()
        self.finished = threading.Event()
        self._phase = "new"
        self._phone_fp: str | None = None
        self._pc_nonce: str | None = None
        self._expires: int | None = None
        self._ticket: str | None = None
        self._offset = 0

    def _metadata(self) -> dict[str, object]:
        return {
            "file_name": self.selected.name,
            "size_bytes": self.selected.size,
            "sha256": self.selected.sha256,
            "chunk_bytes": CHUNK_BYTES,
        }

    def begin(
        self, *, invitation: str, phone_fp: str, phone_nonce: str,
        approve_pc_file: Callable[[str, int], bool],
    ) -> dict[str, object]:
        now = int(time.time())
        if (now >= self.qr_expires or not self.identity.finished.is_set()
                or self.identity.verified_phone_fingerprint is None
                or not isinstance(invitation, str)
                or not hmac.compare_digest(invitation, self.invitation)
                or not isinstance(phone_fp, str)
                or _HEX32.fullmatch(phone_fp) is None
                or not hmac.compare_digest(
                    phone_fp, self.identity.verified_phone_fingerprint)
                or not isinstance(phone_nonce, str)
                or _HEX32.fullmatch(phone_nonce) is None):
            raise PermissionError("Incomplete real QR-v3 mutual identity")
        with self._lock:
            if self._phase != "new":
                raise PermissionError("Transfer request already consumed")
            self._phase = "pc_consent"
        try:
            if approve_pc_file(self.selected.name, self.selected.size) is not True:
                raise PermissionError("PC user refused file transfer")
            now = int(time.time())
            if now >= self.qr_expires:
                raise PermissionError("QR invitation expired")
            expires = min(now + MAX_SESSION_SECONDS, self.qr_expires)
            pc_nonce = secrets.token_hex(32)
            proof = self.signer(
                invitation=self.invitation, tls_fingerprint=self.tls,
                peer_fingerprint=phone_fp, nonce=scoped_nonce(phone_nonce),
                expires_at=expires,
            )
            if not verify_identity_proof(
                proof, expected_signer_fingerprint=self.pc_fp, role="pc",
                invitation=self.invitation, tls_fingerprint=self.tls,
                peer_fingerprint=phone_fp, nonce=scoped_nonce(phone_nonce),
                expires_at=expires, now_epoch_seconds=now,
            ):
                raise PermissionError("Wrong PC file-specific signature")
            with self._lock:
                if self._phase != "pc_consent":
                    raise PermissionError("Transfer revoked while approving")
                self._phase = "await_phone"
                self._phone_fp = phone_fp
                self._pc_nonce = pc_nonce
                self._expires = expires
            return {
                "protocol": PROTOCOL, "status": "challenge",
                "pc_nonce": pc_nonce, "expires": expires,
                "pc_proof": proof, "file": self._metadata(),
            }
        except BaseException:
            self.cancel()
            raise

    def finish(
        self, *, invitation: str, phone_fp: str,
        phone_proof: Mapping[str, str],
    ) -> dict[str, object]:
        with self._lock:
            if self._phase != "await_phone":
                raise PermissionError("No approved transfer awaiting phone")
            self._phase = "checking"  # one use before cryptographic work
            expected = self._phone_fp
            nonce = self._pc_nonce
            expires = self._expires
        try:
            now = int(time.time())
            if (now >= expires or not self.identity.finished.is_set()
                    or self.identity.verified_phone_fingerprint is None
                    or not isinstance(invitation, str)
                    or not hmac.compare_digest(invitation, self.invitation)
                    or not isinstance(phone_fp, str)
                    or not hmac.compare_digest(phone_fp, expected)
                    or not hmac.compare_digest(
                        phone_fp, self.identity.verified_phone_fingerprint)):
                raise PermissionError("Expired or mismatched file proof")
            if not verify_identity_proof(
                phone_proof, expected_signer_fingerprint=expected,
                role="android", invitation=self.invitation,
                tls_fingerprint=self.tls, peer_fingerprint=self.pc_fp,
                nonce=scoped_nonce(nonce), expires_at=expires,
                now_epoch_seconds=now,
            ):
                raise PermissionError("Invalid new Android file-only signature")
            with self._lock:
                if self._phase != "checking":
                    raise PermissionError("Transfer cancelled")
                self._ticket = secrets.token_hex(16)
                self._phase = "sending"
                return {
                    "protocol": PROTOCOL, "status": "ready",
                    "pc_nonce": nonce, "ticket": self._ticket,
                    "expires": expires, "file": self._metadata(),
                }
        except BaseException:
            self.cancel()
            raise

    def chunk(self, *, ticket: str, offset: int) -> dict[str, object]:
        with self._lock:
            if (self._phase != "sending" or type(ticket) is not str
                    or _HEX16.fullmatch(ticket) is None
                    or self._ticket is None
                    or not hmac.compare_digest(ticket, self._ticket)
                    or type(offset) is not int or offset != self._offset
                    or time.time() >= self._expires
                    or not self.identity.finished.is_set()):
                raise PermissionError("Invalid, expired or replayed chunk")
            start = self._offset
            end = min(start + CHUNK_BYTES, self.selected.size)
            portion = self.selected.content[start:end]
            # Advance before responding. Retrying any chunk is NOT permitted.
            self._offset = end
            done = end == self.selected.size
            response = {
                "protocol": PROTOCOL, "status": "chunk",
                "offset": start, "next_offset": end,
                "data": base64.b64encode(portion).decode("ascii"),
                "done": done,
            }
            if done:
                self.cancel()
            return response

    def cancel_by_ticket(self, ticket: str) -> bool:
        """Only the active owner of the TLS-held one-time ticket can cancel."""
        with self._lock:
            if (self._phase != "sending" or type(ticket) is not str
                    or _HEX16.fullmatch(ticket) is None
                    or self._ticket is None
                    or not hmac.compare_digest(ticket, self._ticket)):
                return False
            self.cancel()
            return True

    def cancel(self) -> None:
        with self._lock:
            self._phase = "closed"
            self._ticket = None
            self._phone_fp = None
            self._pc_nonce = None
            self._expires = None
            self.finished.set()

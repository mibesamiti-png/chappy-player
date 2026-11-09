"""R5B: one Android-selected 4 MiB upload to one PC-owner-selected destination.

Opt-in only after real QR-v3 proof, separate PC RECEIVE and Android consent,
new pc.file.upload P-256 proofs, QR-pinned TLS, one-time sequential chunks.
No remote paths, arbitrary directory listing, overwrites, or auto listeners.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import os
from pathlib import Path
import re
import secrets
import tempfile
import threading
import time
from collections.abc import Callable, Mapping

from identity_proof import sign_pc_challenge, verify_identity_proof
from file_send_once import safe_name

PROTOCOL = "pc-file-upload-v1"
SCOPE = "pc.file.upload"
MAX_FILE_BYTES = 4 * 1024 * 1024
CHUNK_BYTES = 16 * 1024
MAX_SECONDS = 240
_HEX16 = re.compile(r"[0-9a-f]{32}\Z")
_HEX32 = re.compile(r"[0-9a-f]{64}\Z")


def scoped_nonce(raw: str) -> str:
    if type(raw) is not str or _HEX32.fullmatch(raw) is None:
        raise ValueError("Bad one-time upload nonce")
    return hashlib.sha256(
        b"CHAPPY-PC-FILE-UPLOAD-V1\x00" + bytes.fromhex(raw)
    ).hexdigest()


class SelectedDestination:
    """PC owner chooses an ABSOLUTE new, local filename before server starts."""
    def __init__(self, path_text: str):
        if type(path_text) is not str or not path_text.strip():
            raise ValueError("Choose an absolute destination on the PC")
        path = Path(path_text.strip().strip('"'))
        if (not path.is_absolute() or ".." in path.parts
                or str(path).startswith(("\\\\", "//"))):
            raise ValueError("No relative or UNC destinations")
        self.name = safe_name(path.name)
        parent = path.parent
        if parent.is_symlink() or not parent.is_dir() or path.is_symlink():
            raise ValueError("Destination must be a regular local directory")
        if path.exists():
            raise ValueError("Destination already exists; no overwrite")
        # Resolve once, never receive paths from Android.
        self.path = path
        self.parent = parent

    def save_verified(self, contents: bytes) -> None:
        """New temp file, fsync, atomic hard-link no-clobber, guaranteed cleanup."""
        if type(contents) is not bytes or not 1 <= len(contents) <= MAX_FILE_BYTES:
            raise ValueError("Invalid upload size")
        if self.path.exists() or self.path.is_symlink() or self.parent.is_symlink():
            raise PermissionError("Destination changed or already exists")
        fd, temporary = tempfile.mkstemp(prefix=".chappy-upload-", dir=str(self.parent))
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(contents)
                stream.flush()
                os.fsync(stream.fileno())
            # os.link fails atomically if destination exists (unlike os.replace).
            os.link(temporary, self.path)
        finally:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass


class FileUploadOnceAttempt:
    def __init__(
        self, *, identity, invitation: str, qr_expires: int,
        tls_fingerprint: str, pc_fingerprint: str,
        destination: SelectedDestination,
        signer: Callable[..., dict[str, str]] = sign_pc_challenge,
    ) -> None:
        if (type(invitation) is not str or not _HEX16.fullmatch(invitation)
                or type(tls_fingerprint) is not str
                or not _HEX32.fullmatch(tls_fingerprint)
                or type(pc_fingerprint) is not str
                or not _HEX32.fullmatch(pc_fingerprint)
                or type(qr_expires) is not int or qr_expires <= 0
                or not isinstance(destination, SelectedDestination)):
            raise ValueError("Invalid selected destination/QR bootstrap")
        self.identity = identity
        self.invitation = invitation
        self.qr_expires = qr_expires
        self.tls = tls_fingerprint
        self.pc_fp = pc_fingerprint
        self.destination = destination
        self.signer = signer
        self.finished = threading.Event()
        self._lock = threading.RLock()
        self._phase = "new"
        self._phone_fp: str | None = None
        self._nonce: str | None = None
        self._expires: int | None = None
        self._ticket: str | None = None
        self._offset = 0
        self._bytes = bytearray()
        self._expected_size = 0
        self._expected_sha = ""

    def begin(self, *, invitation: str, phone_fp: str, phone_nonce: str,
              name: str, size_bytes: int, sha256: str,
              approve_pc_upload: Callable[[str, int], bool]) -> dict[str, object]:
        now = int(time.time())
        if (now >= self.qr_expires or not self.identity.finished.is_set()
                or self.identity.verified_phone_fingerprint is None
                or type(invitation) is not str
                or not hmac.compare_digest(invitation, self.invitation)
                or type(phone_fp) is not str
                or not _HEX32.fullmatch(phone_fp)
                or not hmac.compare_digest(phone_fp, self.identity.verified_phone_fingerprint)
                or type(phone_nonce) is not str or not _HEX32.fullmatch(phone_nonce)
                or type(name) is not str or name != self.destination.name
                or type(size_bytes) is not int or not 1 <= size_bytes <= MAX_FILE_BYTES
                or type(sha256) is not str or not _HEX32.fullmatch(sha256)):
            raise PermissionError("No matching verified identity and PC-selected file")
        with self._lock:
            if self._phase != "new":
                raise PermissionError("Upload already attempted")
            self._phase = "pc_consent"
        try:
            if approve_pc_upload(name, size_bytes) is not True:
                raise PermissionError("PC user declined upload")
            now = int(time.time())
            if now >= self.qr_expires:
                raise PermissionError("QR expired")
            expires = min(now + MAX_SECONDS, self.qr_expires)
            nonce = secrets.token_hex(32)
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
                raise PermissionError("PC upload proof mismatch")
            with self._lock:
                if self._phase != "pc_consent":
                    raise PermissionError("Upload cancelled")
                self._phone_fp = phone_fp
                self._nonce = nonce
                self._expires = expires
                self._expected_size = size_bytes
                self._expected_sha = sha256
                self._phase = "await_phone"
            return {
                "protocol": PROTOCOL, "status": "challenge",
                "pc_nonce": nonce, "expires": expires,
                "pc_proof": proof, "file": {
                    "file_name": name, "size_bytes": size_bytes,
                    "sha256": sha256, "chunk_bytes": CHUNK_BYTES,
                },
            }
        except BaseException:
            self.cancel()
            raise

    def finish(self, *, invitation: str, phone_fp: str,
               phone_proof: Mapping[str, str]) -> dict[str, object]:
        with self._lock:
            if self._phase != "await_phone":
                raise PermissionError("Upload proof not pending")
            self._phase = "checking"
            expected, nonce, expires = self._phone_fp, self._nonce, self._expires
        try:
            now = int(time.time())
            if (now >= expires or not self.identity.finished.is_set()
                    or self.identity.verified_phone_fingerprint is None
                    or type(invitation) is not str
                    or not hmac.compare_digest(invitation, self.invitation)
                    or type(phone_fp) is not str
                    or not hmac.compare_digest(phone_fp, expected)
                    or not hmac.compare_digest(
                        phone_fp, self.identity.verified_phone_fingerprint)):
                raise PermissionError("Expired or wrong phone upload proof")
            if not verify_identity_proof(
                phone_proof, expected_signer_fingerprint=expected,
                role="android", invitation=self.invitation, tls_fingerprint=self.tls,
                peer_fingerprint=self.pc_fp, nonce=scoped_nonce(nonce),
                expires_at=expires, now_epoch_seconds=now,
            ):
                raise PermissionError("Upload Android signature invalid")
            with self._lock:
                if self._phase != "checking":
                    raise PermissionError("Cancelled upload")
                self._phase = "receiving"
                self._ticket = secrets.token_hex(16)
                return {"protocol": PROTOCOL, "status": "ready",
                        "ticket": self._ticket, "pc_nonce": nonce,
                        "expires": expires}
        except BaseException:
            self.cancel()
            raise

    def append(self, *, ticket: str, offset: int,
               data: str) -> dict[str, object]:
        with self._lock:
            if (self._phase != "receiving" or type(ticket) is not str
                    or not _HEX16.fullmatch(ticket) or self._ticket is None
                    or not hmac.compare_digest(ticket, self._ticket)
                    or type(offset) is not int or offset != self._offset
                    or time.time() >= self._expires
                    or not self.identity.finished.is_set()
                    or type(data) is not str or not 1 <= len(data) <= 22000
                    or re.fullmatch(r"[A-Za-z0-9+/]+={0,2}", data) is None):
                raise PermissionError("Invalid chunk, expiry or replay")
            try:
                chunk = base64.b64decode(data, validate=True)
            except (ValueError, base64.binascii.Error):
                self.cancel()
                raise PermissionError("Invalid upload encoding")
            remaining = self._expected_size - self._offset
            if (len(chunk) < 1 or len(chunk) > CHUNK_BYTES
                    or len(chunk) != min(CHUNK_BYTES, remaining)):
                self.cancel()
                raise PermissionError("Invalid chunk size")
            self._bytes.extend(chunk)
            self._offset += len(chunk)
            done = self._offset == self._expected_size
            return {"protocol": PROTOCOL, "status": "received",
                    "next_offset": self._offset, "done": done}

    def commit(self, *, ticket: str, size_bytes: int,
               sha256: str) -> dict[str, object]:
        with self._lock:
            if (self._phase != "receiving" or type(ticket) is not str
                    or not _HEX16.fullmatch(ticket) or self._ticket is None
                    or not hmac.compare_digest(ticket, self._ticket)
                    or type(size_bytes) is not int or size_bytes != self._expected_size
                    or type(sha256) is not str or sha256 != self._expected_sha
                    or self._offset != self._expected_size
                    or time.time() >= self._expires):
                raise PermissionError("Upload not ready for commit")
            self._phase = "committing"
            try:
                data = bytes(self._bytes)
                if hashlib.sha256(data).hexdigest() != self._expected_sha:
                    raise PermissionError("Upload SHA256 mismatch")
                self.destination.save_verified(data)
                return {"protocol": PROTOCOL, "status": "saved",
                        "size_bytes": len(data), "sha256": self._expected_sha}
            finally:
                self.cancel()

    def cancel_by_ticket(self, ticket: str) -> bool:
        with self._lock:
            if self._ticket is None or type(ticket) is not str or \
                    not _HEX16.fullmatch(ticket) or \
                    not hmac.compare_digest(ticket, self._ticket):
                return False
            self.cancel()
            return True

    def cancel(self) -> None:
        with self._lock:
            self._phase = "closed"
            self._ticket = None
            self._phone_fp = None
            self._nonce = None
            self._expires = None
            self._expected_sha = ""
            self._bytes.clear()
            self.finished.set()

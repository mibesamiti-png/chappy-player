"""Explicit QR-v3 PC-side mutual proof transport over a separately pinned TLS socket.

Only used by --start --pair --qr --identity-qr. It does not run at boot,
authorize PC commands, persist pairing, transfer files or grant future trust.
Android support is deliberately a separate change: QR-v2 remains untouched.
"""
from __future__ import annotations

import base64
import binascii
import hashlib
import hmac
import json
import re
import threading
import time
from http.server import BaseHTTPRequestHandler
from typing import Callable, Mapping

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from identity_proof import canonical_challenge
from mutual_proof_session import MutualProofSession

MAX_REQUEST_BYTES = 1536
MAX_REPLY_BYTES = 2048
HEX32 = re.compile(r"[a-f0-9]{64}\Z")
HEX16 = re.compile(r"[a-f0-9]{32}\Z")


def strict_json_object(raw: bytes) -> dict[str, object]:
    """Reject duplicate JSON field names, including in nested proof objects."""
    def unique_object(items: list[tuple[str, object]]) -> dict[str, object]:
        result: dict[str, object] = {}
        for name, value in items:
            if name in result:
                raise ValueError("Duplicate JSON field")
            result[name] = value
        return result

    parsed = json.loads(raw, object_pairs_hook=unique_object)
    if not isinstance(parsed, dict):
        raise ValueError("Expected JSON object")
    return parsed


def verified_android_fingerprint(encoded: str) -> str:
    """Parse a canonical, bounded P-256 SPKI DER supplied by the phone."""
    if not isinstance(encoded, str) or len(encoded) > 344:
        raise ValueError("Invalid phone identity encoding length")
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ValueError("Invalid phone identity base64") from exc
    if not 1 <= len(raw) <= 256 or base64.b64encode(raw).decode("ascii") != encoded:
        raise ValueError("Non-canonical phone public key")
    key = serialization.load_der_public_key(raw)
    if not isinstance(key, ec.EllipticCurvePublicKey) or not isinstance(
        key.curve, ec.SECP256R1
    ):
        raise ValueError("Only P-256 phone identities are supported")
    canonical = key.public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    if raw != canonical:
        raise ValueError("Non-canonical SPKI DER")
    return hashlib.sha256(raw).hexdigest()


def pc_comparison_code(phone_nonce: str) -> str:
    if not isinstance(phone_nonce, str) or not HEX32.fullmatch(phone_nonce):
        raise ValueError("Phone nonce must be 32 random bytes in hex")
    return hashlib.sha256(bytes.fromhex(phone_nonce)).hexdigest()[:6].upper()


class QrProofSession:
    """Stateful PC-side verifier; one begin and one finish, no persistence."""

    def __init__(
        self, *, invitation: str, tls_fingerprint: str,
        pc_fingerprint: str, expires_at: int,
        ask_pc_user: Callable[[str], bool],
        sign_pc: Callable[..., Mapping[str, str]],
    ) -> None:
        if not isinstance(invitation, str) or not HEX16.fullmatch(invitation):
            raise ValueError("Invalid QR invitation")
        if type(expires_at) is not int or expires_at < 1:
            raise ValueError("Invalid QR expiration")
        canonical_challenge(
            role="pc", invitation=invitation,
            tls_fingerprint=tls_fingerprint, peer_fingerprint=pc_fingerprint,
            nonce="0" * 64, expires_at=expires_at,
        )
        self.invitation = invitation
        self.expires_at = expires_at
        self.tls_fingerprint = tls_fingerprint
        self.pc_fingerprint = pc_fingerprint
        self._ask_pc_user = ask_pc_user
        self._sign_pc = sign_pc
        self._lock = threading.Lock()
        self._claimed = False
        self._proof_state: MutualProofSession | None = None
        self._started = False
        self._finished = False
        self._finish_deadline = 0
        self.finished = threading.Event()

    def _expiry_check(self) -> None:
        if time.time() >= self.expires_at:
            raise ValueError("QR invitation expired")

    def begin(self, request: Mapping[str, object]) -> dict[str, object]:
        """Consume one QR invite after strict parsing, then ask PC user."""
        if not isinstance(request, dict) or set(request) != {
            "protocol", "invitation", "phone_nonce", "android_spki",
        } or request.get("protocol") != "pair-proof-v3":
            raise ValueError("Invalid proof start payload")
        invitation = request["invitation"]
        nonce = request["phone_nonce"]
        if not isinstance(invitation, str) or not HEX16.fullmatch(invitation):
            raise ValueError("Invalid invitation")
        if not isinstance(nonce, str):
            raise ValueError("Invalid nonce")
        code = pc_comparison_code(nonce)
        android_fp = verified_android_fingerprint(request["android_spki"])
        if hmac.compare_digest(android_fp, self.pc_fingerprint):
            raise ValueError("Phone and PC identity must differ")
        if not hmac.compare_digest(invitation, self.invitation):
            raise ValueError("Wrong QR invitation")

        with self._lock:
            self._expiry_check()
            if self._claimed or self._finished:
                raise ValueError("QR invitation was already claimed")
            self._claimed = True  # even a refusal cannot re-open this invite
        try:
            print("==== CHAPPY PC MUTUAL IDENTITY PREVIEW ====")
            print("Phone comparison code: " + code)
            print("Approve only when your own phone shows this exact code.")
            print("No saved pairing, PC control or file access is granted.")
            if self._ask_pc_user(code) is not True:
                raise ValueError("PC confirmation rejected")
            self._expiry_check()
            state = MutualProofSession(
                invitation=self.invitation,
                tls_fingerprint=self.tls_fingerprint,
                pc_fingerprint=self.pc_fingerprint,
                android_fingerprint=android_fp,
                phone_issued_nonce=nonce,
                expires_at=self.expires_at,
            )
            pc_req = state.android_issued_request_for_pc
            pc_proof = dict(self._sign_pc(
                invitation=pc_req.invitation,
                tls_fingerprint=pc_req.tls_fingerprint,
                peer_fingerprint=pc_req.peer_fingerprint,
                nonce=pc_req.nonce,
                expires_at=pc_req.expires_at,
            ))
            if not state.submit_proof(signer="pc", response=pc_proof):
                raise ValueError("PC local proof failed")
            with self._lock:
                if self._finished:
                    raise ValueError("Session was cancelled")
                self._proof_state = state
                self._started = True
                # Reduce post-approval exposure even if QR lifetime is 10 min.
                self._finish_deadline = min(self.expires_at, int(time.time()) + 20)
            return {
                "status": "challenge",
                "protocol": "pair-proof-v3",
                "pc_fingerprint": self.pc_fingerprint,
                "pc_nonce": state.pc_issued_request_for_android.nonce,
                "expires_at": self.expires_at,
                "pc_proof": pc_proof,
            }
        except Exception:
            with self._lock:
                self._finished = True
                if self._proof_state is not None:
                    self._proof_state.cancel()
            self.finished.set()
            raise

    def finish(self, request: Mapping[str, object]) -> dict[str, str]:
        """Accept just one approved and valid phone proof, then close forever."""
        with self._lock:
            if self._finished or not self._started:
                raise ValueError("No pending mutual proof")
            self._finished = True
            state = self._proof_state
            deadline = self._finish_deadline
        try:
            if int(time.time()) >= deadline or state is None:
                raise ValueError("Phone proof was not received in time")
            if not isinstance(request, dict) or set(request) != {
                "protocol", "invitation", "phone_approved", "android_proof",
            } or request["protocol"] != "pair-proof-v3":
                raise ValueError("Invalid phone proof payload")
            invitation = request["invitation"]
            if not isinstance(invitation, str) or not hmac.compare_digest(
                invitation, self.invitation
            ):
                raise ValueError("Wrong QR invitation")
            if request["phone_approved"] is not True:
                raise ValueError("Phone user did not approve")
            proof = request["android_proof"]
            if not isinstance(proof, dict) or not all(
                isinstance(v, str) for v in proof.values()
            ):
                raise ValueError("Invalid Android signature")
            if not state.submit_proof(signer="android", response=proof):
                raise ValueError("Android identity proof invalid")
            if not state.approve(side="pc", approved=True):
                raise ValueError("PC approval missing")
            if not state.approve(side="android", approved=True):
                raise ValueError("Phone approval missing")
            if not state.complete():
                raise ValueError("Mutual confirmation incomplete")
            return {"protocol": "pair-proof-v3", "status": "verified"}
        finally:
            if state is not None:
                state.cancel()
            self.finished.set()

    def cancel(self) -> None:
        with self._lock:
            self._finished = True
            if self._proof_state is not None:
                self._proof_state.cancel()
        self.finished.set()


def make_qr_proof_handler(state: QrProofSession):
    class Handler(BaseHTTPRequestHandler):
        server_version = "ChappyProofPreview/1.0"
        sys_version = ""

        def setup(self) -> None:
            super().setup()
            self.connection.settimeout(5.0)

        def log_message(self, _format: str, *_args: object) -> None:
            # Never log IPs, identities, QR invitations, signatures, or headers.
            pass

        def _reply(self, code: int, payload: Mapping[str, object]) -> None:
            raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            if len(raw) > MAX_REPLY_BYTES:
                code = 500
                raw = b'{"status":"not_available"}'
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(raw)
            self.close_connection = True

        def do_GET(self) -> None:
            self._reply(405, {"status": "not_supported"})

        def do_POST(self) -> None:
            if self.path not in ("/v3/proof-begin", "/v3/proof-finish"):
                self._reply(404, {"status": "not_found"})
                return
            lengths = self.headers.get_all("Content-Length", [])
            if len(lengths) != 1:
                self._reply(400, {"status": "bad_request"})
                return
            length = lengths[0]
            if (len(length) > 5 or not length.isascii()
                    or not length.isdecimal()):
                self._reply(400, {"status": "bad_request"})
                return
            size = int(length)
            if size < 1 or size > MAX_REQUEST_BYTES:
                self._reply(413, {"status": "bad_size"})
                return
            if self.headers.get("Content-Type") != "application/json":
                self._reply(415, {"status": "unsupported_type"})
                return
            try:
                body = self.rfile.read(size)
                if len(body) != size:
                    raise ValueError("Incomplete JSON")
                value = strict_json_object(body)
                if self.path == "/v3/proof-begin":
                    response = state.begin(value)
                else:
                    response = state.finish(value)
                self._reply(200, response)
            except (ValueError, TypeError, KeyError, UnicodeDecodeError):
                self._reply(403, {"status": "rejected"})
            except (OSError, RuntimeError):
                state.cancel()
                self._reply(503, {"status": "not_available"})
    return Handler

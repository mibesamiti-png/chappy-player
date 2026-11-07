"""One-session HTTPS confirmation for a user-operated Windows PC.

NOT persistent pairing or authorization for any PC command/telemetry.
A fresh self-signed certificate is displayed as a SHA-256 fingerprint in
the console. Android must manually enter the FULL fingerprint before TLS.
The server then asks for an independent, short-lived PC-console approval.

Never save the key, private user information, credentials, or packet contents.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import hmac
import ipaddress
import json
import queue
import secrets
import socket
import ssl
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from typing import TYPE_CHECKING
from windows_identity import identity_status

if TYPE_CHECKING:
    from identity_pairing_v3 import IdentityPairingAttempt

IDENTITY_PROTOCOL = "pair-identity-v3"

from companion import (
    MAX_MINUTES,
    service_descriptor,
    validate_lan_ipv4,
)

MAX_REQUEST = 256
MAX_IDENTITY_REQUEST = 2048
MAX_APPROVAL_SECONDS = 25
MAX_INVITE_SECONDS = 600


class PairingSession:
    def __init__(
        self, invitation: str | None = None, expires_at: float = 0.0
    ) -> None:
        if invitation is not None and not (
            len(invitation) == 32 and all(c in "0123456789abcdef" for c in invitation)
        ):
            raise ValueError("Invite token must be 16 random bytes in lowercase hex")
        self.invitation = invitation
        self.expires_at = expires_at
        self.claimed = False
        self.finished = threading.Event()
        self.lock = threading.Lock()

    def claim(self, invitation: str | None = None) -> bool:
        with self.lock:
            if self.claimed:
                return False
            if self.invitation is not None:
                if (
                    not isinstance(invitation, str)
                    or not hmac.compare_digest(invitation, self.invitation)
                    or time.time() >= self.expires_at
                ):
                    return False
            elif invitation is not None:
                return False
            self.claimed = True
            return True


def confirmation_code(nonce: str) -> str:
    if len(nonce) != 32 or any(c not in "0123456789abcdef" for c in nonce):
        raise ValueError("Expected exactly 16 bytes of lowercase hex nonce")
    return hashlib.sha256(bytes.fromhex(nonce)).hexdigest()[:6].upper()


def create_ephemeral_certificate(ip: str) -> tuple[bytes, bytes, str]:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.x509.oid import NameOID

    address = validate_lan_ipv4(ip)
    now = dt.datetime.now(dt.timezone.utc)
    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, "Chappy Companion Session")
    ])
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - dt.timedelta(minutes=1))
        .not_valid_after(now + dt.timedelta(minutes=MAX_MINUTES + 2))
        .add_extension(x509.SubjectAlternativeName([
            x509.IPAddress(ipaddress.IPv4Address(address))
        ]), critical=False)
        .sign(private_key=key, algorithm=hashes.SHA256())
    )
    pem = cert.public_bytes(serialization.Encoding.PEM)
    key_pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    return pem, key_pem, cert.fingerprint(hashes.SHA256()).hex()


def _ask_pc_user(nonce: str) -> bool:
    if len(nonce) == 64:
        from identity_pairing_v3 import comparison_code
        code = comparison_code(nonce)
    else:
        code = confirmation_code(nonce)
    print()
    print("==== PHONE CONFIRMATION REQUEST ====")
    print("Code shown on phone: " + code)
    print("Approve ONLY if your own phone shows this exact code.")
    print("This does not grant file access, remote control or future trust.")
    answer: queue.Queue[str] = queue.Queue(maxsize=1)

    def read_console() -> None:
        try:
            answer.put(input("Approve this one-time confirmation? Type YES: ").strip())
        except (EOFError, OSError):
            answer.put("")

    threading.Thread(target=read_console, daemon=True).start()
    try:
        return answer.get(timeout=MAX_APPROVAL_SECONDS) == "YES"
    except queue.Empty:
        print("Confirmation timed out; this session will close.")
        return False


def invite_payload(ip: str, port: int, fingerprint: str,
                   token: str, expires_at: int,
                   identity_fingerprint: str | None = None) -> str:
    """Strict, short-lived QR transfer string; nothing grants PC commands."""
    validate_lan_ipv4(ip)
    if not 1 <= port <= 65535:
        raise ValueError("Invalid port")
    if len(fingerprint) != 64 or any(c not in "0123456789abcdef" for c in fingerprint):
        raise ValueError("Invalid certificate pin")
    if len(token) != 32 or any(c not in "0123456789abcdef" for c in token):
        raise ValueError("Invalid invitation")
    if expires_at <= 0:
        raise ValueError("Invalid expiry")
    if identity_fingerprint is not None and (
        len(identity_fingerprint) != 64 or
        any(c not in "0123456789abcdef" for c in identity_fingerprint)
    ):
        raise ValueError("Invalid persistent PC identity fingerprint")
    version = "v3" if identity_fingerprint is not None else "v2"
    return (
        "chappy-pair://" + version + "?ip=" + ip + "&port=" + str(port)
        + "&fp=" + fingerprint + "&inv=" + token + "&exp=" + str(expires_at)
        + ("&pc=" + identity_fingerprint if identity_fingerprint is not None else "")
    )


def render_qr(invitation: str) -> str:
    """Half-height block QR to fit a standard 80-column Windows terminal."""
    import qrcode

    qr = qrcode.QRCode(border=4, error_correction=qrcode.constants.ERROR_CORRECT_M)
    qr.add_data(invitation)
    qr.make(fit=True)
    cells = qr.get_matrix()
    rows = []
    for y in range(0, len(cells), 2):
        row = ""
        for x in range(len(cells[0])):
            top = cells[y][x]
            bottom = cells[y + 1][x] if y + 1 < len(cells) else False
            row += (
                "\u2588" if top and bottom else
                "\u2580" if top else
                "\u2584" if bottom else " "
            )
        rows.append(row)
    return "\n".join(rows)


def make_handler(session: PairingSession,
                 identity: IdentityPairingAttempt | None = None):
    class PairHandler(BaseHTTPRequestHandler):
        server_version = "ChappyPairPreview/1.0"
        sys_version = ""

        def setup(self) -> None:
            super().setup()
            self.connection.settimeout(5.0)

        def log_message(self, format: str, *args: object) -> None:
            # Never log remote IP addresses or pair challenges to disk.
            pass

        def _reply(self, code: int, result: dict[str, object]) -> None:
            payload = json.dumps(result, separators=(",", ":")).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(payload)
            self.close_connection = True

        def do_GET(self) -> None:
            self._reply(405, {"status": "not_supported"})

        def _handle_identity(self) -> None:
            if identity is None or self.path not in (
                "/v3/identity-begin", "/v3/identity-finish",
            ):
                self._reply(404, {"status": "not_found"})
                return
            length_text = self.headers.get("Content-Length", "")
            if not length_text.isascii() or not length_text.isdecimal():
                self._reply(400, {"status": "bad_request"})
                return
            length = int(length_text)
            if not 1 <= length <= MAX_IDENTITY_REQUEST:
                self._reply(413, {"status": "too_large"})
                return
            if self.headers.get("Content-Type") != "application/json":
                self._reply(415, {"status": "unsupported_type"})
                return
            try:
                data = json.loads(self.rfile.read(length))
                if not isinstance(data, dict) or data.get("protocol") != IDENTITY_PROTOCOL:
                    raise ValueError("Invalid identity protocol")
                if self.path == "/v3/identity-begin":
                    if set(data) != {
                        "protocol", "invitation", "phone_nonce", "phone_fp",
                    }:
                        raise ValueError("Invalid begin fields")
                    def approve(phone_nonce: str) -> bool:
                        print("Phone's PUBLIC identity fingerprint:")
                        print(data["phone_fp"])
                        print("Compare the confirmation code on BOTH devices.")
                        return _ask_pc_user(phone_nonce)
                    answer = identity.begin(
                        invitation=data["invitation"],
                        phone_fingerprint=data["phone_fp"],
                        phone_nonce=data["phone_nonce"],
                        approve_on_pc=approve,
                    )
                else:
                    if set(data) != {
                        "protocol", "invitation", "phone_fp", "phone_proof",
                    } or not isinstance(data["phone_proof"], dict):
                        raise ValueError("Invalid finish fields")
                    answer = identity.finish(
                        invitation=data["invitation"],
                        phone_fingerprint=data["phone_fp"],
                        phone_proof=data["phone_proof"],
                    )
                self._reply(200, answer)
            except (ValueError, TypeError, KeyError, PermissionError, OSError):
                # Do not reveal secrets or the reason a public identity failed.
                self._reply(403, {"status": "identity_denied"})

        def do_POST(self) -> None:
            if self.path.startswith("/v3/"):
                self._handle_identity()
                return
            if self.path != "/v1/pair-preview":
                self._reply(404, {"status": "not_found"})
                return
            length_text = self.headers.get("Content-Length", "")
            if not length_text.isascii() or not length_text.isdecimal():
                self._reply(400, {"status": "bad_request"})
                return
            length = int(length_text)
            if not 1 <= length <= MAX_REQUEST:
                self._reply(413, {"status": "too_large"})
                return
            if self.headers.get("Content-Type") != "application/json":
                self._reply(415, {"status": "unsupported_type"})
                return
            try:
                data = json.loads(self.rfile.read(length))
                if not isinstance(data, dict):
                    raise ValueError("Invalid JSON object")
                if session.invitation is None:
                    if set(data) != {"protocol", "nonce"} or data["protocol"] != "pair-preview-v1":
                        raise ValueError("Unsupported legacy request")
                else:
                    if set(data) != {"protocol", "nonce", "invitation"} or data["protocol"] != "pair-qr-v2":
                        raise ValueError("QR invitation required")
                nonce = data["nonce"]
                if not isinstance(nonce, str):
                    raise ValueError("Invalid nonce")
                confirmation_code(nonce)
            except (ValueError, UnicodeDecodeError, TypeError):
                self._reply(400, {"status": "bad_request"})
                return

            if session.invitation is not None:
                supplied = data.get("invitation")
                if not isinstance(supplied, str) or not session.claim(supplied):
                    self._reply(403, {"status": "invalid_or_expired_invitation"})
                    return
            elif not session.claim():
                self._reply(409, {"status": "already_requested"})
                return
            try:
                approved = _ask_pc_user(nonce)
                self._reply(
                    200 if approved else 403,
                    {"status": "approved" if approved else "denied",
                     "protocol": "pair-qr-v2" if session.invitation is not None
                        else "pair-preview-v1", "nonce": nonce},
                )
            finally:
                session.finished.set()

    return PairHandler


class BoundedHttpsServer(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 4

    def __init__(self, address, handler):
        super().__init__(address, handler)
        self.timeout = 0.4
        self._active = threading.BoundedSemaphore(4)

    def get_request(self):
        # Accept plain TCP first and limit the TLS handshake lifetime.
        # Wrapping the listening socket directly may block on a silent client.
        connection, address = self.socket.accept()
        connection.settimeout(3.0)
        try:
            wrapped = self.context.wrap_socket(connection, server_side=True)
            return wrapped, address
        except Exception:
            connection.close()
            raise

    def process_request(self, request, client_address):
        if not self._active.acquire(blocking=False):
            try:
                request.close()
            finally:
                return
        try:
            super().process_request(request, client_address)
        except Exception:
            self._active.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self._active.release()


def run_pairing(ip: str, minutes: int, qr: bool = False,
                identity_mode: bool = False) -> None:
    """Expose a single, explicitly PC-approved HTTPS confirmation session."""
    from zeroconf import IPVersion, ServiceInfo, Zeroconf

    address = validate_lan_ipv4(ip)
    if not 1 <= minutes <= MAX_MINUTES:
        raise ValueError("Duration must be 1-30 minutes")
    if identity_mode and not qr:
        raise ValueError("Identity enrollment requires a scanned QR")
    # Never create a persistent signing key when a PC listener is started.
    pc_public_fingerprint = identity_status() if identity_mode else None
    if identity_mode and pc_public_fingerprint is None:
        raise ValueError("Create PC identity explicitly before v3 enrollment")
    if identity_mode:
        from identity_pairing_v3 import IdentityPairingAttempt
    pem, key, fingerprint = create_ephemeral_certificate(address)

    with tempfile.TemporaryDirectory(prefix="chappy-pair-session-") as folder:
        crt = Path(folder) / "session.crt"
        pem_key = Path(folder) / "session.key"
        crt.write_bytes(pem)
        pem_key.write_bytes(key)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(str(crt), str(pem_key))
        # Do not leave long-lived plaintext key material in temporary storage.
        pem_key.unlink(missing_ok=True)
        crt.unlink(missing_ok=True)

        lifetime_seconds = min(minutes * 60, MAX_INVITE_SECONDS) if qr else minutes * 60
        expires_at = int(time.time() + lifetime_seconds)
        invitation = secrets.token_hex(16) if qr else None
        session = PairingSession(invitation=invitation, expires_at=expires_at)
        identity = (
            IdentityPairingAttempt(
                invitation=invitation, qr_expires=expires_at,
                tls_fingerprint=fingerprint, pc_fingerprint=pc_public_fingerprint,
            ) if identity_mode else None
        )
        with BoundedHttpsServer(
            (address, 0), make_handler(session, identity),
        ) as server:
            server.context = context
            port = server.server_address[1]
            nonce = secrets.token_hex(4)
            details = service_descriptor(address, port, nonce)
            details["properties"] = {
                b"app": b"chappy", b"mode": b"pair-preview-v1",
            }
            info = ServiceInfo(**details)
            zeroconf = Zeroconf(
                interfaces=[address], ip_version=IPVersion.V4Only
            )
            registered = False
            try:
                zeroconf.register_service(info, allow_name_change=False)
                registered = True
                print("Chappy Companion: secure confirmation preview ON")
                print("PC IPv4: " + address + "  TLS port: " + str(port))
                print("Service: " + info.name)
                print("FULL SHA-256 certificate fingerprint (copy to phone):")
                print(fingerprint)
                if qr:
                    assert invitation is not None
                    invite_text = invite_payload(
                        address, port, fingerprint, invitation, expires_at,
                        identity_fingerprint=pc_public_fingerprint,
                    )
                    print("Scan this QR on your Android Chappy Network Lab:")
                    # The terminal may use a legacy encoding. Do not log the
                    # raw invitation token in that fallback.
                    try:
                        print(render_qr(invite_text))
                    except UnicodeEncodeError:
                        print("Terminal lacks UTF-8 QR glyphs. Run chcp 65001.")
                print("This fingerprint is generated fresh at every start.")
                print("Your PC must separately approve one phone request.")
                if identity_mode:
                    print("Identity v3: mutual signed proof ONLY; no saved pairing.")
                print("Auto-stop: " + str(minutes) + " min. Ctrl+C stops.")
                deadline = time.monotonic() + lifetime_seconds
                finished = identity.finished if identity is not None else session.finished
                while time.monotonic() < deadline and not finished.is_set():
                    try:
                        server.handle_request()
                    except (ssl.SSLError, OSError):
                        # A client may interrupt TLS handshakes; do not
                        # terminate the user's short-lived invitation.
                        continue
            finally:
                try:
                    if registered:
                        zeroconf.unregister_service(info)
                finally:
                    zeroconf.close()
                    print("Chappy Companion: secure confirmation preview OFF")

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

from companion import (
    MAX_MINUTES,
    service_descriptor,
    validate_lan_ipv4,
)

MAX_REQUEST = 256
MAX_APPROVAL_SECONDS = 25


class PairingSession:
    def __init__(self) -> None:
        self.claimed = False
        self.finished = threading.Event()
        self.lock = threading.Lock()

    def claim(self) -> bool:
        with self.lock:
            if self.claimed:
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


def make_handler(session: PairingSession):
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

        def do_POST(self) -> None:
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
                if not isinstance(data, dict) or set(data) != {
                    "protocol", "nonce"
                } or data["protocol"] != "pair-preview-v1":
                    raise ValueError("Unsupported request")
                nonce = data["nonce"]
                if not isinstance(nonce, str):
                    raise ValueError("Invalid nonce")
                confirmation_code(nonce)
            except (ValueError, UnicodeDecodeError, TypeError):
                self._reply(400, {"status": "bad_request"})
                return

            if not session.claim():
                self._reply(409, {"status": "already_requested"})
                return
            try:
                approved = _ask_pc_user(nonce)
                self._reply(
                    200 if approved else 403,
                    {"status": "approved" if approved else "denied",
                     "protocol": "pair-preview-v1", "nonce": nonce},
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


def run_pairing(ip: str, minutes: int) -> None:
    """Expose a single, explicitly PC-approved HTTPS confirmation session."""
    from zeroconf import IPVersion, ServiceInfo, Zeroconf

    address = validate_lan_ipv4(ip)
    if not 1 <= minutes <= MAX_MINUTES:
        raise ValueError("Duration must be 1-30 minutes")
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

        session = PairingSession()
        with BoundedHttpsServer((address, 0), make_handler(session)) as server:
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
                print("This fingerprint is generated fresh at every start.")
                print("Your PC must separately approve one phone request.")
                print("Auto-stop: " + str(minutes) + " min. Ctrl+C stops.")
                deadline = time.monotonic() + minutes * 60
                while time.monotonic() < deadline and not session.finished.is_set():
                    server.handle_request()
            finally:
                try:
                    if registered:
                        zeroconf.unregister_service(info)
                finally:
                    zeroconf.close()
                    print("Chappy Companion: secure confirmation preview OFF")

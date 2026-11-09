"""PC Link R5A: real QR-v3 P-256 proof + separate one-file scoped transfer tests.

Transport in the localhost handler fixture is intentionally HTTP only for
unit testing. Production LAN uses the QR-pinned ephemeral HTTPS listener.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from unittest import mock

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "examples/windows_companion"))

import companion
import identity_pairing_v3 as v3
import identity_proof as proof
import pairing_server as server
from file_send_once import (
    FileSendOnceAttempt, SelectedFile, safe_name, scoped_nonce, PROTOCOL,
    CHUNK_BYTES, MAX_FILE_BYTES,
)

INV = "a" * 32
TLS = "b" * 64
PHONE_NONCE = "c" * 64


def fp(key):
    spki = key.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return hashlib.sha256(spki).hexdigest()


class FileSendTests(unittest.TestCase):
    def setUp(self):
        self.pc = ec.generate_private_key(ec.SECP256R1())
        self.phone = ec.generate_private_key(ec.SECP256R1())
        self.pc_fp, self.phone_fp = fp(self.pc), fp(self.phone)
        self.expiry = int(time.time()) + 300
        self.pc_sign = lambda **kwargs: proof._sign_with_key(
            self.pc, role="pc", **kwargs,
        )
        self.identity = v3.IdentityPairingAttempt(
            invitation=INV, qr_expires=self.expiry,
            tls_fingerprint=TLS, pc_fingerprint=self.pc_fp,
            signer=self.pc_sign,
        )
        self.data = b"A" * (CHUNK_BYTES + 37)
        self.selected = SelectedFile(name="photo-demo.bin", content=self.data)
        self.sender = self.fresh_sender()

    def fresh_sender(self):
        return FileSendOnceAttempt(
            identity=self.identity, invitation=INV,
            qr_expires=self.expiry, tls_fingerprint=TLS,
            pc_fingerprint=self.pc_fp,
            selected=self.selected, signer=self.pc_sign,
        )

    def authenticate(self):
        challenge = self.identity.begin(
            invitation=INV, phone_fingerprint=self.phone_fp,
            phone_nonce=PHONE_NONCE,
            approve_on_pc=lambda _: True,
        )
        signed = proof._sign_with_key(
            self.phone, role="android", invitation=INV,
            tls_fingerprint=TLS, peer_fingerprint=self.pc_fp,
            nonce=challenge["pc_nonce"], expires_at=challenge["expires"],
        )
        self.assertEqual(
            self.identity.finish(
                invitation=INV, phone_fingerprint=self.phone_fp,
                phone_proof=signed,
            )["status"],
            "approved",
        )

    def begin(self, approve=None):
        return self.sender.begin(
            invitation=INV, phone_fp=self.phone_fp,
            phone_nonce=PHONE_NONCE,
            approve_pc_file=approve or (lambda _, __: True),
        )

    def sign(self, challenge, key=None, scoped=True):
        return proof._sign_with_key(
            key or self.phone, role="android",
            invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=self.pc_fp,
            nonce=(scoped_nonce(challenge["pc_nonce"])
                   if scoped else challenge["pc_nonce"]),
            expires_at=challenge["expires"],
        )

    def test_identity_proof_alone_and_fingerprint_history_cannot_read_file(self):
        consent = mock.Mock(return_value=True)
        with self.assertRaises(PermissionError):
            self.begin(consent)
        consent.assert_not_called()
        self.authenticate()
        self.assertFalse(self.sender.finished.is_set())
        # The original QR-v3 approval is not new file permission.
        with self.assertRaises(PermissionError):
            self.begin(lambda _, __: False)
        self.assertTrue(self.sender.finished.is_set())
        with self.assertRaises(PermissionError):
            self.begin()

    def test_signed_file_challenge_cannot_be_used_as_status_or_identity_proof(self):
        self.authenticate()
        result = self.begin()
        self.assertEqual(result["protocol"], PROTOCOL)
        self.assertEqual(result["file"]["sha256"],
                         hashlib.sha256(self.data).hexdigest())
        self.assertTrue(proof.verify_identity_proof(
            result["pc_proof"], expected_signer_fingerprint=self.pc_fp,
            role="pc", invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=self.phone_fp,
            nonce=scoped_nonce(PHONE_NONCE), expires_at=result["expires"],
        ))
        self.assertFalse(proof.verify_identity_proof(
            result["pc_proof"], expected_signer_fingerprint=self.pc_fp,
            role="pc", invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=self.phone_fp, nonce=PHONE_NONCE,
            expires_at=result["expires"],
        ))
        self.assertNotEqual(scoped_nonce(PHONE_NONCE),
                            hashlib.sha256(
                                b"CHAPPY-PC-STATUS-READ-V1\x00"
                                + bytes.fromhex(PHONE_NONCE)).hexdigest())

    def test_fresh_android_file_signature_releases_one_sequential_download(self):
        self.authenticate()
        challenge = self.begin()
        ready = self.sender.finish(
            invitation=INV, phone_fp=self.phone_fp,
            phone_proof=self.sign(challenge),
        )
        self.assertEqual(ready["status"], "ready")
        self.assertEqual(ready["file"]["size_bytes"], len(self.data))
        ticket = ready["ticket"]
        with self.assertRaises(PermissionError):
            self.sender.chunk(ticket=ticket, offset=1)
        with self.assertRaises(PermissionError):
            self.sender.chunk(ticket="0" * 32, offset=0)
        first = self.sender.chunk(ticket=ticket, offset=0)
        self.assertEqual(first["next_offset"], CHUNK_BYTES)
        self.assertFalse(first["done"])
        with self.assertRaises(PermissionError):
            self.sender.chunk(ticket=ticket, offset=0)
        second = self.sender.chunk(ticket=ticket, offset=CHUNK_BYTES)
        self.assertTrue(second["done"])
        self.assertTrue(self.sender.finished.is_set())
        import base64
        rebuilt = base64.b64decode(first["data"]) + base64.b64decode(second["data"])
        self.assertEqual(rebuilt, self.data)
        self.assertEqual(hashlib.sha256(rebuilt).hexdigest(),
                         ready["file"]["sha256"])
        with self.assertRaises(PermissionError):
            self.sender.chunk(ticket=ticket, offset=len(self.data))

    def test_wrong_phone_key_and_wrong_scope_close_session_without_file(self):
        self.authenticate()
        other = fp(ec.generate_private_key(ec.SECP256R1()))
        with self.assertRaises(PermissionError):
            self.sender.begin(
                invitation=INV, phone_fp=other, phone_nonce=PHONE_NONCE,
                approve_pc_file=lambda _, __: self.fail("No consent prompt"),
            )
        c = self.begin()
        with self.assertRaises(PermissionError):
            self.sender.finish(
                invitation=INV, phone_fp=self.phone_fp,
                phone_proof=self.sign(c, scoped=False),
            )
        self.assertTrue(self.sender.finished.is_set())

    def test_expiry_and_cancel_by_active_ticket(self):
        self.authenticate()
        c = self.begin()
        ready = self.sender.finish(
            invitation=INV, phone_fp=self.phone_fp,
            phone_proof=self.sign(c),
        )
        self.assertFalse(self.sender.cancel_by_ticket("0" * 32))
        self.assertTrue(self.sender.cancel_by_ticket(ready["ticket"]))
        with self.assertRaises(PermissionError):
            self.sender.chunk(ticket=ready["ticket"], offset=0)
        self.assertFalse(self.sender.cancel_by_ticket(ready["ticket"]))
        self.sender = self.fresh_sender()
        c = self.begin()
        ready = self.sender.finish(
            invitation=INV, phone_fp=self.phone_fp,
            phone_proof=self.sign(c),
        )
        self.sender._expires = int(time.time()) - 1
        with self.assertRaises(PermissionError):
            self.sender.chunk(ticket=ready["ticket"], offset=0)

    def test_selected_file_is_local_bounded_single_snapshot_only(self):
        for name in ("../private.txt", "/tmp/a", r"..\secret.txt",
                     ".", "..", "a\x00b", "end."):
            with self.assertRaises(ValueError, msg=name):
                safe_name(name)
        for size in (0, MAX_FILE_BYTES + 1):
            with self.assertRaises(ValueError):
                SelectedFile(name="valid.txt", content=b"x" * size)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "notice.txt"
            path.write_bytes(b"only preselected content")
            chosen = SelectedFile.from_local_selection(str(path))
            self.assertEqual(chosen.content, path.read_bytes())
            self.assertEqual(chosen.name, "notice.txt")
            with self.assertRaises(ValueError):
                SelectedFile.from_local_selection(str(Path(folder)))
            with self.assertRaises(ValueError):
                SelectedFile.from_local_selection("some-relative-file.txt")

    def test_http_strict_local_fixture_and_no_legacy_file_endpoints(self):
        self.authenticate()
        old = server.PairingSession(invitation=INV, expires_at=self.expiry)
        httpd = ThreadingHTTPServer(
            ("127.0.0.1", 0),
            server.make_handler(old, self.identity, None, self.sender),
        )
        worker = threading.Thread(target=httpd.serve_forever, daemon=True)
        worker.start()

        def post(path, data):
            request = urllib.request.Request(
                "http://127.0.0.1:" + str(httpd.server_port) + path,
                data=json.dumps(data).encode("utf-8"),
                headers={"Content-Type": "application/json"},
            )
            return urllib.request.urlopen(request, timeout=5)

        begin = {"protocol": PROTOCOL, "invitation": INV,
                 "phone_fp": self.phone_fp, "phone_nonce": PHONE_NONCE}
        try:
            with self.assertRaises(urllib.error.HTTPError) as bad:
                post("/v3/file-begin", dict(begin, path="/private"))
            self.assertEqual(bad.exception.code, 403)
            with mock.patch.object(server, "_ask_pc_file_user",
                                   return_value=True) as ask:
                with post("/v3/file-begin", begin) as response:
                    challenge = json.load(response)
                ask.assert_called_once_with("photo-demo.bin", len(self.data))
            with post("/v3/file-finish", {
                "protocol": PROTOCOL, "invitation": INV,
                "phone_fp": self.phone_fp, "phone_proof": self.sign(challenge),
            }) as response:
                ready = json.load(response)
            with post("/v3/file-chunk", {
                "protocol": PROTOCOL, "ticket": ready["ticket"], "offset": 0,
            }) as response:
                first = json.load(response)
            self.assertEqual(first["next_offset"], CHUNK_BYTES)
            with self.assertRaises(urllib.error.HTTPError) as replay:
                post("/v3/file-chunk", {
                    "protocol": PROTOCOL, "ticket": ready["ticket"],
                    "offset": 0,
                })
            self.assertEqual(replay.exception.code, 403)
            with post("/v3/file-chunk", {
                "protocol": PROTOCOL, "ticket": ready["ticket"],
                "offset": CHUNK_BYTES,
            }) as response:
                self.assertTrue(json.load(response)["done"])
        finally:
            httpd.shutdown()
            httpd.server_close()
            worker.join(timeout=3)

    def test_qr_explicit_file_scope_and_cli_never_autostart(self):
        qr = server.invite_payload(
            "192.168.1.7", 49152, TLS, INV, self.expiry,
            identity_fingerprint=self.pc_fp, file_once=True,
        )
        self.assertTrue(qr.endswith("&file=1"))
        with self.assertRaises(ValueError):
            server.invite_payload(
                "192.168.1.7", 49152, TLS, INV, self.expiry,
                file_once=True,
            )
        self.assertEqual(companion.main(["--send-file-once"]), 2)
        self.assertEqual(companion.main([]), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)

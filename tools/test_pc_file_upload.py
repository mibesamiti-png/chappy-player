"""R5B: bounded Android->Windows file upload with real P-256 proof, no-clobber.

HTTP localhost fixture tests only; real LAN requires pinned TLS and
the physical Android↔Windows device matrix (still NOT RUN).
"""
from __future__ import annotations

import base64
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
import pairing_server
from file_upload_once import (
    SelectedDestination, FileUploadOnceAttempt, scoped_nonce,
    PROTOCOL, CHUNK_BYTES, MAX_FILE_BYTES,
)
from file_send_once import scoped_nonce as download_scope
from status_once import scoped_nonce as status_scope

INV = "a" * 32
TLS = "b" * 64
PHONE_NONCE = "c" * 64


def fingerprint(key):
    raw = key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    return hashlib.sha256(raw).hexdigest()


class UploadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.destination = Path(self.temp.name) / "demo.bin"
        self.pc = ec.generate_private_key(ec.SECP256R1())
        self.phone = ec.generate_private_key(ec.SECP256R1())
        self.pc_fp = fingerprint(self.pc)
        self.phone_fp = fingerprint(self.phone)
        self.expiry = int(time.time()) + 300
        self.pc_sign = lambda **kwargs: proof._sign_with_key(
            self.pc, role="pc", **kwargs)
        self.data = b"DATA" * (CHUNK_BYTES // 4 + 7)
        self.digest = hashlib.sha256(self.data).hexdigest()
        self.identity = v3.IdentityPairingAttempt(
            invitation=INV, qr_expires=self.expiry,
            tls_fingerprint=TLS, pc_fingerprint=self.pc_fp,
            signer=self.pc_sign,
        )
        self.upload = self.fresh()

    def fresh(self):
        return FileUploadOnceAttempt(
            identity=self.identity, invitation=INV,
            qr_expires=self.expiry, tls_fingerprint=TLS,
            pc_fingerprint=self.pc_fp, signer=self.pc_sign,
            destination=SelectedDestination(str(self.destination)),
        )

    def authenticate(self):
        begin = self.identity.begin(
            invitation=INV, phone_fingerprint=self.phone_fp,
            phone_nonce=PHONE_NONCE, approve_on_pc=lambda _: True,
        )
        sig = proof._sign_with_key(
            self.phone, role="android",
            invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=self.pc_fp, nonce=begin["pc_nonce"],
            expires_at=begin["expires"])
        answer = self.identity.finish(
            invitation=INV, phone_fingerprint=self.phone_fp,
            phone_proof=sig)
        self.assertEqual(answer["status"], "approved")

    def begin(self, approve=lambda _, __: True):
        return self.upload.begin(
            invitation=INV, phone_fp=self.phone_fp,
            phone_nonce=PHONE_NONCE, name=self.destination.name,
            size_bytes=len(self.data), sha256=self.digest,
            approve_pc_upload=approve,
        )

    def sign(self, challenge, *, scope=True, key=None):
        return proof._sign_with_key(
            key or self.phone, role="android",
            invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=self.pc_fp,
            nonce=(scoped_nonce(challenge["pc_nonce"]) if scope
                   else challenge["pc_nonce"]),
            expires_at=challenge["expires"])

    def authorize(self):
        challenge = self.begin()
        self.assertTrue(proof.verify_identity_proof(
            challenge["pc_proof"], expected_signer_fingerprint=self.pc_fp,
            role="pc", invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=self.phone_fp,
            nonce=scoped_nonce(PHONE_NONCE),
            expires_at=challenge["expires"]))
        return self.upload.finish(
            invitation=INV, phone_fp=self.phone_fp,
            phone_proof=self.sign(challenge))

    def test_identity_alone_never_writes_without_separate_consent(self):
        ask = mock.Mock(return_value=True)
        with self.assertRaises(PermissionError):
            self.begin(ask)
        ask.assert_not_called()
        self.authenticate()
        with self.assertRaises(PermissionError):
            self.begin(lambda _, __: False)
        self.assertTrue(self.upload.finished.is_set())
        self.assertFalse(self.destination.exists())
        with self.assertRaises(PermissionError):
            self.begin()

    def test_one_file_sequential_chunks_sha256_atomic_no_clobber(self):
        self.authenticate()
        ready = self.authorize()
        self.assertEqual(ready["protocol"], PROTOCOL)
        ticket = ready["ticket"]
        with self.assertRaises(PermissionError):
            self.upload.append(ticket=ticket, offset=1, data="AAAA")
        first = self.upload.append(
            ticket=ticket, offset=0,
            data=base64.b64encode(self.data[:CHUNK_BYTES]).decode())
        self.assertEqual(first["next_offset"], CHUNK_BYTES)
        self.assertFalse(first["done"])
        with self.assertRaises(PermissionError):
            self.upload.append(ticket=ticket, offset=0, data="AAAA")
        second = self.upload.append(
            ticket=ticket, offset=CHUNK_BYTES,
            data=base64.b64encode(self.data[CHUNK_BYTES:]).decode())
        self.assertTrue(second["done"])
        saved = self.upload.commit(
            ticket=ticket, size_bytes=len(self.data), sha256=self.digest)
        self.assertEqual(saved["status"], "saved")
        self.assertEqual(self.destination.read_bytes(), self.data)
        self.assertTrue(self.upload.finished.is_set())
        with self.assertRaises(PermissionError):
            self.upload.commit(
                ticket=ticket, size_bytes=len(self.data), sha256=self.digest)
        self.assertEqual(list(Path(self.temp.name).iterdir()), [self.destination])

    def test_broken_hash_and_failed_commit_leave_no_file(self):
        self.authenticate()
        ready = self.authorize()
        ticket = ready["ticket"]
        corrupt = b"X" + self.data[1:]
        for offset in range(0, len(corrupt), CHUNK_BYTES):
            self.upload.append(
                ticket=ticket, offset=offset,
                data=base64.b64encode(
                    corrupt[offset:offset + CHUNK_BYTES]).decode())
        with self.assertRaises(PermissionError):
            self.upload.commit(
                ticket=ticket, size_bytes=len(corrupt), sha256=self.digest)
        self.assertFalse(self.destination.exists())
        self.assertEqual(list(Path(self.temp.name).iterdir()), [])

    def test_destination_existing_file_no_overwrite_and_unrelated_paths(self):
        with self.assertRaises(ValueError):
            SelectedDestination("relative.bin")
        with self.assertRaises(ValueError):
            SelectedDestination(str(Path(self.temp.name) / ".." / "bad.bin"))
        # Only the exact basename can be submitted; no remote path parameter.
        self.authenticate()
        with self.assertRaises(PermissionError):
            self.upload.begin(
                invitation=INV, phone_fp=self.phone_fp,
                phone_nonce=PHONE_NONCE, name="../secret.bin",
                size_bytes=len(self.data), sha256=self.digest,
                approve_pc_upload=lambda *_: self.fail("PC must not prompt"))
        ready = self.authorize()
        ticket = ready["ticket"]
        for offset in range(0, len(self.data), CHUNK_BYTES):
            self.upload.append(ticket=ticket, offset=offset,
                data=base64.b64encode(self.data[offset:offset + CHUNK_BYTES]).decode())
        self.destination.write_bytes(b"KEEP")
        with self.assertRaises((PermissionError, FileExistsError)):
            self.upload.commit(
                ticket=ticket, size_bytes=len(self.data), sha256=self.digest)
        self.assertEqual(self.destination.read_bytes(), b"KEEP")
        self.assertEqual(list(Path(self.temp.name).iterdir()), [self.destination])

    def test_invalid_signature_scope_ticket_and_cancel_do_not_write(self):
        self.authenticate()
        self.assertNotEqual(scoped_nonce(PHONE_NONCE), download_scope(PHONE_NONCE))
        self.assertNotEqual(scoped_nonce(PHONE_NONCE), status_scope(PHONE_NONCE))
        challenge = self.begin()
        with self.assertRaises(PermissionError):
            self.upload.finish(
                invitation=INV, phone_fp=self.phone_fp,
                phone_proof=self.sign(challenge, scope=False))
        self.assertFalse(self.destination.exists())
        self.upload = self.fresh()
        challenge = self.begin()
        ready = self.upload.finish(
            invitation=INV, phone_fp=self.phone_fp,
            phone_proof=self.sign(challenge))
        self.assertFalse(self.upload.cancel_by_ticket("0" * 32))
        self.assertTrue(self.upload.cancel_by_ticket(ready["ticket"]))
        self.assertFalse(self.upload.cancel_by_ticket(ready["ticket"]))
        self.assertFalse(self.destination.exists())

    def test_file_length_limit_and_cli_explicit_opt_in(self):
        with self.assertRaises(ValueError):
            SelectedDestination(str(Path(self.temp.name) / "dir" / "demo.bin"))
        self.authenticate()
        with self.assertRaises(PermissionError):
            self.upload.begin(
                invitation=INV, phone_fp=self.phone_fp,
                phone_nonce=PHONE_NONCE, name="demo.bin",
                size_bytes=MAX_FILE_BYTES + 1, sha256=self.digest,
                approve_pc_upload=lambda *_: True)
        self.assertEqual(companion.main(["--receive-file-once"]), 2)
        self.assertEqual(companion.main(["--start", "--receive-file-once"]), 2)
        self.assertEqual(companion.main([]), 0)
        qr = pairing_server.invite_payload(
            "192.168.1.8", 443, TLS, INV, self.expiry,
            identity_fingerprint=self.pc_fp, upload_once=True)
        self.assertTrue(qr.endswith("&upload=1"))
        with self.assertRaises(ValueError):
            pairing_server.invite_payload(
                "192.168.1.8", 443, TLS, INV, self.expiry,
                identity_fingerprint=self.pc_fp,
                file_once=True, upload_once=True)

    def test_strict_http_handler_with_real_proof_localhost_only(self):
        self.authenticate()
        session = pairing_server.PairingSession(
            invitation=INV, expires_at=self.expiry)
        httpd = ThreadingHTTPServer(
            ("127.0.0.1", 0),
            pairing_server.make_handler(
                session, self.identity, None, None, self.upload))
        worker = threading.Thread(target=httpd.serve_forever, daemon=True)
        worker.start()
        def send(path, fields):
            req = urllib.request.Request(
                f"http://127.0.0.1:{httpd.server_port}{path}",
                data=json.dumps(fields).encode(),
                headers={"Content-Type": "application/json"})
            return urllib.request.urlopen(req, timeout=5)
        data = {
            "protocol": PROTOCOL, "invitation": INV,
            "phone_fp": self.phone_fp, "phone_nonce": PHONE_NONCE,
            "file_name": "demo.bin", "size_bytes": len(self.data),
            "sha256": self.digest,
        }
        try:
            with self.assertRaises(urllib.error.HTTPError) as e:
                send("/v3/upload-begin", dict(data, remote_path="../"))
            self.assertEqual(e.exception.code, 403)
            with mock.patch.object(pairing_server, "_ask_pc_upload_user",
                                   return_value=True):
                with send("/v3/upload-begin", data) as r:
                    challenge = json.load(r)
            with send("/v3/upload-finish", {
                "protocol": PROTOCOL, "invitation": INV,
                "phone_fp": self.phone_fp,
                "phone_proof": self.sign(challenge),
            }) as r:
                ready = json.load(r)
            for offset in range(0, len(self.data), CHUNK_BYTES):
                with send("/v3/upload-chunk", {
                    "protocol": PROTOCOL, "ticket": ready["ticket"],
                    "offset": offset,
                    "data": base64.b64encode(
                        self.data[offset:offset + CHUNK_BYTES]).decode(),
                }) as r:
                    result = json.load(r)
                    self.assertEqual(result["next_offset"],
                                     min(offset + CHUNK_BYTES, len(self.data)))
            with send("/v3/upload-commit", {
                "protocol": PROTOCOL, "ticket": ready["ticket"],
                "size_bytes": len(self.data), "sha256": self.digest,
            }) as r:
                result = json.load(r)
            self.assertEqual(result["status"], "saved")
            self.assertEqual(self.destination.read_bytes(), self.data)
        finally:
            httpd.shutdown()
            httpd.server_close()
            worker.join(timeout=3)


if __name__ == "__main__":
    unittest.main(verbosity=2)

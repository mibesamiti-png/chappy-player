"""R6B isolated localhost HTTP integration with genuine P-256 signatures.

Deliberately plain HTTP on 127.0.0.1 IN TEST ONLY. Production uses QR-pinned
TLS. Windows multimedia execution is injected as a mock, never invoked here.
This does not substitute for Android↔Windows physical QA.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import sys
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

import identity_pairing_v3 as v3
import identity_proof as proof
import media_control_once as media_module
import pairing_server as server
from media_control_once import MediaOnceAttempt, scoped_nonce, PROTOCOL
from status_once import scoped_nonce as status_scope

INV, TLS, PHONE_NONCE = "a" * 32, "b" * 64, "c" * 64


def fingerprint(key):
    der = key.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return hashlib.sha256(der).hexdigest()


class MediaHttpIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.pc_key = ec.generate_private_key(ec.SECP256R1())
        self.android_key = ec.generate_private_key(ec.SECP256R1())
        self.pc_fp = fingerprint(self.pc_key)
        self.phone_fp = fingerprint(self.android_key)
        self.expires = int(time.time()) + 240
        pc_sign = lambda **kw: proof._sign_with_key(self.pc_key, role="pc", **kw)
        self.identity = v3.IdentityPairingAttempt(
            invitation=INV, qr_expires=self.expires,
            tls_fingerprint=TLS, pc_fingerprint=self.pc_fp,
            signer=pc_sign,
        )
        self.executed = []
        self.media = MediaOnceAttempt(
            identity=self.identity, invitation=INV, qr_expires=self.expires,
            tls_fingerprint=TLS, pc_fingerprint=self.pc_fp,
            signer=pc_sign, executor=self.executed.append,
        )
        legacy = server.PairingSession(invitation=INV, expires_at=self.expires)
        handler = server.make_handler(
            legacy, identity=self.identity, media_once=self.media,
        )
        self.http = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.worker = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.worker.start()

    def tearDown(self):
        self.http.shutdown()
        self.http.server_close()
        self.worker.join(timeout=3)

    def post(self, path, body, *, content_type="application/json", raw=False):
        data = body if raw else json.dumps(body, separators=(",", ":")).encode()
        request = urllib.request.Request(
            "http://127.0.0.1:" + str(self.http.server_port) + path,
            data=data, headers={"Content-Type": content_type},
        )
        with urllib.request.urlopen(request, timeout=5) as answer:
            self.assertEqual(200, answer.status)
            return json.load(answer)

    def expect_denied(self, path, body, code=403, *, raw=False, content_type="application/json"):
        with self.assertRaises(urllib.error.HTTPError) as denied:
            self.post(path, body, raw=raw, content_type=content_type)
        self.assertEqual(code, denied.exception.code)

    def sign(self, nonce, expires, *, command=None, status=False, key=None):
        if command is not None:
            nonce = status_scope(nonce) if status else scoped_nonce(nonce, command)
        return proof._sign_with_key(
            key or self.android_key, role="android", invitation=INV,
            tls_fingerprint=TLS, peer_fingerprint=self.pc_fp,
            nonce=nonce, expires_at=expires,
        )

    def authorize_identity(self):
        begin = {"protocol": "pair-identity-v3", "invitation": INV,
                 "phone_fp": self.phone_fp, "phone_nonce": PHONE_NONCE}
        with mock.patch.object(server, "_ask_pc_user", return_value=True) as consent:
            challenge = self.post("/v3/identity-begin", begin)
        consent.assert_called_once()
        self.assertTrue(proof.verify_identity_proof(
            challenge["pc_proof"], expected_signer_fingerprint=self.pc_fp,
            role="pc", invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=self.phone_fp, nonce=PHONE_NONCE,
            expires_at=challenge["expires"],
        ))
        approved = self.post("/v3/identity-finish", {
            "protocol": "pair-identity-v3", "invitation": INV,
            "phone_fp": self.phone_fp,
            "phone_proof": self.sign(challenge["pc_nonce"], challenge["expires"]),
        })
        self.assertEqual("approved", approved["status"])

    def begin_media(self, cmd="volume_up", pc_approval=True):
        begin = {"protocol": PROTOCOL, "invitation": INV, "phone_fp": self.phone_fp,
                 "phone_nonce": PHONE_NONCE, "command": cmd}
        with mock.patch.object(server, "_ask_pc_media_user",
                               return_value=pc_approval) as approve:
            if not pc_approval:
                self.expect_denied("/v3/media-begin", begin)
                approve.assert_called_once_with(cmd)
                return None
            response = self.post("/v3/media-begin", begin)
        approve.assert_called_once_with(cmd)
        self.assertEqual(cmd, response["command"])
        self.assertTrue(proof.verify_identity_proof(
            response["pc_proof"], expected_signer_fingerprint=self.pc_fp,
            role="pc", invitation=INV, tls_fingerprint=TLS,
            peer_fingerprint=self.phone_fp, nonce=scoped_nonce(PHONE_NONCE, cmd),
            expires_at=response["expires"],
        ))
        return response

    def finish(self, c, *, command=None, status=False):
        return self.post("/v3/media-finish", {
            "protocol": PROTOCOL, "invitation": INV,
            "phone_fp": self.phone_fp,
            "phone_proof": self.sign(
                c["pc_nonce"], c["expires"], command=command or c["command"],
                status=status,
            ),
        })

    def test_all_four_real_http_identity_media_proof_and_replay(self):
        # Each subtest creates an isolated fresh QR/identity/server.
        for index, command in enumerate(("volume_up", "volume_down",
                                         "toggle_mute", "play_pause")):
            if index:
                self.tearDown()
                self.setUp()
            with self.subTest(command=command):
                self.expect_denied("/v3/media-begin", {
                    "protocol": PROTOCOL, "invitation": INV,
                    "phone_fp": self.phone_fp, "phone_nonce": PHONE_NONCE,
                    "command": command,
                })
                self.authorize_identity()
                challenge = self.begin_media(command)
                executed = self.finish(challenge)
                self.assertEqual(executed["status"], "executed")
                self.assertEqual(executed["command"], command)
                self.assertEqual(self.executed, [command])
                self.expect_denied("/v3/media-finish", {
                    "protocol": PROTOCOL, "invitation": INV,
                    "phone_fp": self.phone_fp,
                    "phone_proof": self.sign(
                        challenge["pc_nonce"], challenge["expires"], command=command),
                })
                self.assertEqual(self.executed, [command])

    def test_pc_denial_is_terminal_without_android_media_proof(self):
        self.authorize_identity()
        self.begin_media("toggle_mute", pc_approval=False)
        self.assertTrue(self.media.finished.is_set())
        self.expect_denied("/v3/media-begin", {
            "protocol": PROTOCOL, "invitation": INV,
            "phone_fp": self.phone_fp, "phone_nonce": PHONE_NONCE,
            "command": "toggle_mute",
        })
        self.assertEqual([], self.executed)

    def test_wrong_action_scope_device_or_identity_does_not_execute(self):
        self.authorize_identity()
        self.expect_denied("/v3/media-begin", {
            "protocol": PROTOCOL, "invitation": INV,
            "phone_fp": "f" * 64, "phone_nonce": PHONE_NONCE,
            "command": "volume_up",
        })
        with mock.patch.object(server, "_ask_pc_media_user") as consent:
            self.expect_denied("/v3/media-begin", {
                "protocol": PROTOCOL, "invitation": INV,
                "phone_fp": self.phone_fp, "phone_nonce": PHONE_NONCE,
                "command": "powershell",
            })
            consent.assert_not_called()
        challenge = self.begin_media("volume_down")
        self.expect_denied("/v3/media-finish", {
            "protocol": PROTOCOL, "invitation": INV,
            "phone_fp": self.phone_fp,
            "phone_proof": self.sign(
                challenge["pc_nonce"], challenge["expires"], command="volume_up"),
        })
        self.assertEqual([], self.executed)
        self.assertTrue(self.media.finished.is_set())

    def test_cross_scope_status_signature_denied(self):
        self.authorize_identity()
        challenge = self.begin_media("play_pause")
        self.expect_denied("/v3/media-finish", {
            "protocol": PROTOCOL, "invitation": INV,
            "phone_fp": self.phone_fp,
            "phone_proof": self.sign(
                challenge["pc_nonce"], challenge["expires"],
                command="play_pause", status=True),
        })
        self.assertTrue(self.media.finished.is_set())
        self.assertEqual([], self.executed)

    def test_expired_or_cancelled_request_never_dispatches(self):
        self.authorize_identity()
        challenge = self.begin_media()
        with mock.patch.object(media_module.time, "time",
                               return_value=challenge["expires"]):
            self.expect_denied("/v3/media-finish", {
                "protocol": PROTOCOL, "invitation": INV,
                "phone_fp": self.phone_fp,
                "phone_proof": self.sign(
                    challenge["pc_nonce"], challenge["expires"],
                    command="volume_up"),
            })
        self.assertEqual([], self.executed)
        self.assertTrue(self.media.finished.is_set())

    def test_foreground_cancel_or_disconnected_session_not_reusable(self):
        self.authorize_identity()
        challenge = self.begin_media()
        self.media.cancel()  # simulates cancellation/foreground exit
        self.expect_denied("/v3/media-finish", {
            "protocol": PROTOCOL, "invitation": INV,
            "phone_fp": self.phone_fp,
            "phone_proof": self.sign(
                challenge["pc_nonce"], challenge["expires"],
                command="volume_up"),
        })
        self.assertEqual([], self.executed)

    def test_lost_response_cannot_repeat_toggle_or_use_other_routes(self):
        self.authorize_identity()
        challenge = self.begin_media("toggle_mute")
        # Execution succeeded server-side; client disregards the response.
        self.finish(challenge)
        self.expect_denied("/v3/media-finish", {
            "protocol": PROTOCOL, "invitation": INV,
            "phone_fp": self.phone_fp,
            "phone_proof": self.sign(
                challenge["pc_nonce"], challenge["expires"],
                command="toggle_mute"),
        })
        self.expect_denied("/v3/media-begin", {
            "protocol": PROTOCOL, "invitation": INV,
            "phone_fp": self.phone_fp, "phone_nonce": PHONE_NONCE,
            "command": "play_pause",
        })
        self.expect_denied("/v3/status-begin", {"protocol": PROTOCOL},
                           code=404)
        self.assertEqual(["toggle_mute"], self.executed)

    def test_duplicate_keys_content_type_and_unknown_fields_fail(self):
        self.authorize_identity()
        base = {"protocol": PROTOCOL, "invitation": INV,
                "phone_fp": self.phone_fp, "phone_nonce": PHONE_NONCE,
                "command": "volume_up"}
        self.expect_denied("/v3/media-begin", dict(base, shell="whoami"))
        self.expect_denied("/v3/media-begin", base, code=415,
                           content_type="text/plain")
        duplicate = json.dumps(base).replace(
            '"command": "volume_up"',
            '"command": "volume_up", "command": "volume_down"',
        ).encode()
        self.expect_denied("/v3/media-begin", duplicate, raw=True)
        self.assertEqual([], self.executed)
        # Bad framing is rejected without consuming the one-shot capability.
        challenge = self.begin_media()
        self.assertEqual(challenge["status"], "challenge")


if __name__ == "__main__":
    unittest.main(verbosity=2)

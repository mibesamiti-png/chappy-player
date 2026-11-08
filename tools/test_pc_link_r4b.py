"""R4B fail-closed consent and strict fixture contract tests (no real PC)."""
from __future__ import annotations

import concurrent.futures
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "examples" / "windows_companion"))
from offline_session_preview import (  # noqa: E402
    OfflinePreviewSession, PROTOCOL, STATUS_CAPABILITY,
    MAX_LIFETIME_SECONDS, validate_fixture_response,
)

NOW = 1800000000
EXP = NOW + 60
CONTRACT = ROOT / "docs/pc-link-session-preview-v1.json"


def fresh() -> OfflinePreviewSession:
    return OfflinePreviewSession(now_epoch_seconds=NOW, expires_at=EXP)


def verified() -> OfflinePreviewSession:
    gate = fresh()
    assert gate.verify(identity_verified=True, now_epoch_seconds=NOW)
    return gate


def active() -> OfflinePreviewSession:
    gate = verified()
    assert gate.request_read_only(capability=STATUS_CAPABILITY,
                                  now_epoch_seconds=NOW)
    assert gate.consent(side="pc", approved=True, now_epoch_seconds=NOW)
    assert gate.consent(side="android", approved=True, now_epoch_seconds=NOW)
    return gate


class OfflineSessionTests(unittest.TestCase):
    def test_expiry_and_input_types(self):
        for args in ((NOW, NOW), (NOW, NOW+121), (True, NOW+1),
                     (NOW, False), (NOW, NOW-1)):
            with self.subTest(args=args), self.assertRaises(ValueError):
                OfflinePreviewSession(now_epoch_seconds=args[0], expires_at=args[1])
        self.assertEqual(MAX_LIFETIME_SECONDS, 120)
        self.assertFalse(active().allows(capability=STATUS_CAPABILITY,
                                         now_epoch_seconds=EXP))
        self.assertEqual(active().phase(now_epoch_seconds=EXP), "closed")

    def test_identity_success_is_not_authority(self):
        session = verified()
        self.assertEqual(session.phase(now_epoch_seconds=NOW), "verified")
        self.assertFalse(session.allows(capability=STATUS_CAPABILITY,
                                        now_epoch_seconds=NOW))
        self.assertFalse(session.allows(capability="pc.control",
                                        now_epoch_seconds=NOW))
        self.assertFalse(fresh().request_read_only(
            capability=STATUS_CAPABILITY, now_epoch_seconds=NOW))

    def test_both_new_explicit_approvals_required(self):
        s = verified()
        self.assertTrue(s.request_read_only(capability=STATUS_CAPABILITY,
                                            now_epoch_seconds=NOW))
        self.assertFalse(s.allows(capability=STATUS_CAPABILITY,
                                  now_epoch_seconds=NOW))
        self.assertTrue(s.consent(side="android", approved=True,
                                  now_epoch_seconds=NOW))
        self.assertFalse(s.allows(capability=STATUS_CAPABILITY,
                                  now_epoch_seconds=NOW))
        self.assertTrue(s.consent(side="pc", approved=True,
                                  now_epoch_seconds=NOW))
        self.assertTrue(s.allows(capability=STATUS_CAPABILITY,
                                 now_epoch_seconds=NOW))
        self.assertFalse(s.allows(capability="pc.files.read",
                                  now_epoch_seconds=NOW))

    def test_denial_duplicate_consent_and_capability_are_terminal(self):
        for mutation in ("deny", "repeat", "control", "no_verified", "wrong_side"):
            with self.subTest(mutation=mutation):
                s = verified()
                if mutation == "control":
                    self.assertFalse(s.request_read_only(
                        capability="pc.control", now_epoch_seconds=NOW))
                else:
                    self.assertTrue(s.request_read_only(
                        capability=STATUS_CAPABILITY, now_epoch_seconds=NOW))
                    if mutation == "deny":
                        self.assertFalse(s.consent(
                            side="pc", approved=False, now_epoch_seconds=NOW))
                    elif mutation == "repeat":
                        self.assertTrue(s.consent(
                            side="pc", approved=True, now_epoch_seconds=NOW))
                        self.assertFalse(s.consent(
                            side="pc", approved=True, now_epoch_seconds=NOW))
                    elif mutation == "no_verified":
                        self.assertFalse(s.request_read_only(
                            capability=STATUS_CAPABILITY, now_epoch_seconds=NOW))
                    else:
                        self.assertFalse(s.consent(
                            side="other", approved=True, now_epoch_seconds=NOW))
                self.assertEqual(s.phase(now_epoch_seconds=NOW), "closed")
                self.assertFalse(s.allows(capability=STATUS_CAPABILITY,
                                          now_epoch_seconds=NOW))

    def test_cancel_and_wrong_identity_fail_closed(self):
        s = fresh()
        self.assertFalse(s.verify(identity_verified=False, now_epoch_seconds=NOW))
        self.assertFalse(s.verify(identity_verified=True, now_epoch_seconds=NOW))
        self.assertFalse(s.allows(capability=STATUS_CAPABILITY,
                                  now_epoch_seconds=NOW))
        s = active()
        s.cancel()
        self.assertEqual(s.phase(now_epoch_seconds=NOW), "closed")
        self.assertFalse(s.allows(capability=STATUS_CAPABILITY,
                                  now_epoch_seconds=NOW))

    def test_concurrent_double_approval_invalidates_attempt(self):
        s = verified()
        self.assertTrue(s.request_read_only(capability=STATUS_CAPABILITY,
                                            now_epoch_seconds=NOW))
        def approve(_index):
            return s.consent(side="pc", approved=True,
                             now_epoch_seconds=NOW)
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            values = list(pool.map(approve, range(8)))
        self.assertEqual(values.count(True), 1)
        self.assertEqual(values.count(False), 7)
        self.assertFalse(s.consent(side="android", approved=True,
                                   now_epoch_seconds=NOW))
        self.assertFalse(s.allows(capability=STATUS_CAPABILITY,
                                  now_epoch_seconds=NOW))

    def test_fixture_schema_parity_and_replay(self):
        fixture = json.loads(CONTRACT.read_text(encoding="utf-8"))
        self.assertEqual(fixture["protocol"], PROTOCOL)
        self.assertEqual(fixture["capability"], STATUS_CAPABILITY)
        self.assertEqual(fixture["maxLifetimeSeconds"], MAX_LIFETIME_SECONDS)
        self.assertEqual(fixture["phases"],
                         ["new", "verified", "awaiting_consent", "active", "closed"])
        self.assertEqual(set(fixture["safeFailureCodes"]),
                         {"SESSION-DENIED", "SESSION-EXPIRED", "SESSION-REPLAY",
                          "SESSION-CLOSED", "SESSION-FORMAT"})
        s = active()
        self.assertEqual(s.accept_fixture_request(fixture["request"],
                                                  now_epoch_seconds=NOW),
                         fixture["response"])
        self.assertTrue(validate_fixture_response(fixture["response"], sequence=1))
        self.assertIsNone(s.accept_fixture_request(fixture["request"],
                                                    now_epoch_seconds=NOW))
        self.assertFalse(s.allows(capability=STATUS_CAPABILITY,
                                  now_epoch_seconds=NOW))

    def test_malformed_response_or_request_is_closed(self):
        request = json.loads(CONTRACT.read_text())["request"]
        response = json.loads(CONTRACT.read_text())["response"]
        bad = [dict(request, sequence=True), dict(request, extra="bad"),
               dict(request, kind="pc.control"), dict(request, sequence=0),
               dict(request, capability="pc.control")]
        for payload in bad:
            with self.subTest(payload=payload):
                gate = active()
                self.assertIsNone(gate.accept_fixture_request(payload,
                                                               now_epoch_seconds=NOW))
                self.assertEqual(gate.phase(now_epoch_seconds=NOW), "closed")
        for wrong in [dict(response, sequence=True), dict(response, online=1),
                      dict(response, secret="x"), dict(response, sequence=2)]:
            self.assertFalse(validate_fixture_response(wrong, sequence=1))

    def test_no_network_or_privileged_side_effects_in_preview_core(self):
        import inspect
        from offline_session_preview import OfflinePreviewSession as C
        code = inspect.getsource(C)
        for forbidden in ("socket.", "subprocess.", "os.system",
                          "pickle", "private_key", "open("):
            self.assertNotIn(forbidden, code)
        fixture_script = (ROOT / "tools/pc_link_r4b_loopback_fixture.py").read_text()
        self.assertIn('HTTPServer(("127.0.0.1", 0)', fixture_script)
        self.assertNotIn('"0.0.0.0"', fixture_script)


if __name__ == "__main__":
    unittest.main(verbosity=2)

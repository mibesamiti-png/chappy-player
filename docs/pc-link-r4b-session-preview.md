# PC Link R4B — offline session/capability preview (2026-11-08)

**Source implementation only.** This is NOT deployed as an Android↔Windows connection, credential, PC status API, durable pairing, or authorization service. It neither reads PC metrics nor exposes files or remote commands. Two-device QA remains 0/15.

## Design and security boundaries

1. The existing QR-v3 mutual P-256 proof verifies device identity for one attempt. It does **not** grant PC capabilities or reuse a historical fingerprint as trust.
2. The R4B offline preview starts at new and transitions to verified only via a **test-supplied** boolean. That boolean is NOT authentication and must **never** be wired to an exposed endpoint. Production channel binding to pinned TLS and real QR-v3 proofs is planned for R4C.
3. Only pc.status.read may be requested. Windows and Android must each grant fresh explicit consent before the preview gate becomes active. One-sided consent grants nothing.
4. Each in-memory attempt has a maximum 120-second lifetime. Denial, timeout, duplicate consent, invalid capability, malformed packet, replay or cancel closes it; no persistent token or auto reconnect.
5. The returned online=true value is **simulated test data**, NOT a claim that a real PC is online. The Python fixture binds 127.0.0.1 only and serves one request.

## Files and integration status

| Component | Source | Live/privileged integration |
| --- | --- | --- |
| Python offline consent gate | examples/windows_companion/offline_session_preview.py | Not wired to the Windows Companion EXE or server |
| Dart offline gate | lib/core/pc_link_preview_session.dart | Only Flutter tests import it; no mini-app JS API |
| Strict protocol fixture | docs/pc-link-session-preview-v1.json | Static test vector, no keys or secrets |
| Loopback-only Python fixture | tools/pc_link_r4b_loopback_fixture.py | Test runner only, not packaged into EXE |
| Python behavior + concurrency checks | tools/test_pc_link_r4b.py | CI only |
| Flutter/Dart lifecycle + Python loopback test | test/pc_link_preview_session_test.dart | CI only |
| JS isolation safety check | tools/test_pc_link_r4b_boundary.py | CI only |

Protocol example (fake data):

```json
{"protocol":"pc-link-session-preview-v1","kind":"status-request","sequence":1,"capability":"pc.status.read"}
```

Reply (not real PC status):

```json
{"protocol":"pc-link-session-preview-v1","kind":"status-fixture","sequence":1,"capability":"pc.status.read","online":true}
```

**This protocol is separate from the existing pair-identity-v3.** The real QR-v3 consent, certificate pinning, KeyStore/DPAPI and one-time verification are unchanged.

## Verification and next phase

- Quick CI: Python R4B gates, full Flutter tests including real localhost Python↔Dart fixture, static JS isolation checks.
- Windows Companion Preview: Python gate tests + unchanged explicit EXE. No new privileged PC endpoint.
- Actual Windows/Android 2-device test: NOT RUN, 0/15.
- R4C: bind scope to an authenticated, pinned, fresh QR-v3 session; require per-operation Windows and Android consent; implement truthful read-only status with available/unavailable values, expiry, disconnect, replay protection and JS separation; test real devices before claiming it is usable.

See [QR-v3 design](pc-link-mutual-qr-v3.md), [2-device QA](pc-link-two-device-qa-matrix.md), [handoff state](project/STATE.json).

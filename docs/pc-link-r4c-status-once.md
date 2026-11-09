# PC Link R4C — owner-approved, read-only status once (2026-11-09)

**Source/CI preview. This is not a physical Windows↔Android QA pass.**

## What is implemented

- New **optional** Windows CLI flag `--status-once` that is rejected unless `--start --pair --qr --identity-pair` are explicitly selected. Existing QR-v1/v2/v3 pairing without this flag is unchanged.
- New Windows script `Start-ChappyStatusOnceV3.cmd` and strict QR-v3 opt-in field `status=1` (invalid on QR-v2, duplicate or other values rejected). Regular QR-v3 never grants status scope.
- The original QR-v3 one-shot mutual P-256 device proof is still required. It is NOT a permission grant. Status begin requires that an actual Android proof completed for exactly the PC's QR invite/TLS pin/phone public-key fingerprint.
- Windows **second consent**, after identity proof: the PC owner must explicitly type `STATUS`; original `YES` is insufficient.
- Windows signs a fresh random nonce that is SHA256-domain-separated with `CHAPPY-PC-STATUS-READ-V1\0` from QR-v3 identity usage. Android verifies the pinned PC key and this proof, then asks **another separate Android foreground consent**, signs a fresh scoped nonce with Android KeyStore, and sends status finish.
- Windows verifies the Android public key and signature; only then queries real Windows read-only CPU logical core count, physical memory totals/available, and OS uptime. Unsupported metrics are `null`, not invented zero. No hostname, username, process list, files, IP/MAC, communication data, camera, mic, or remote execution.
- Android displays the metrics in the trusted pairing page only, does not save them, and clears the data on app background/close. No access through `.chappy` JavaScript; no reusable token, file transfer, device control or automatic reconnection.
- A single operation is bounded by the original short QR lifetime and at most **90 seconds** after the identity check. The follow-up nonce is consumed once even on bad proof or consent cancellation.

## Wire shape (status-only, NOT R4B fake fixtures)

1. `POST /v3/identity-begin` and `/v3/identity-finish`: **unchanged** original QR-v3 authenticated ceremony.
2. `POST /v3/status-begin` with protocol `pc-status-once-v1`, original invitation, verified phone fingerprint and a new random phone nonce. Windows separately asks for `STATUS`.
3. Response: signed scoped PC proof, fresh PC nonce, expiry. Android verifies PC key and signature and asks its own on-screen permission.
4. `POST /v3/status-finish`: matching invitation, phone fingerprint, new scoped Android KeyStore proof. Windows replies only with the fixed metrics fields, or a generic denied response.

Both requests are strict JSON with size/framing/duplicate-key limits and are served only by the explicitly opt-in temporary TLS listener. Android must pin the QR's SHA-256 TLS certificate, validate PC public key signature, require QR location match with discovered PC, and perform foreground OS checks inherited from QR-v3.

## Source/tests

- Windows: `examples/windows_companion/status_once.py`, `pc_status_metrics.py`, `pairing_server.py`, `companion.py`.
- Android: `lib/core/pc_status_once.dart`, `companion_identity_exchange.dart`, `companion_qr_invitation.dart`, `lib/screens/companion_pairing_page.dart`.
- CI: `tools/test_pc_status_once.py` (real P-256 proof+localhost handler+provider), `tools/test_pc_status_boundary.py` (no JS/unsafe access), `test/pc_status_once_test.dart` and QR parser unit tests.
- CI localhost HTTP is **test-only**. Actual LAN is pinned TLS; physical Windows↔Android 2-device QA remains **0/15** until tested. No signed Stable APK or public mini-app changes.

## Next

Complete physical device tests, especially PC Windows Firewall/mDNS, Android QR + native KeyStore signatures, both consent prompts, screen lock/Wi-Fi loss, denied status, memory figures and replays. Keep the manual opt-in and short session; do not add always-on monitoring as a shortcut.

Reference: [R4B offline model](pc-link-r4b-session-preview.md) / [QA checklist](pc-link-two-device-qa-matrix.md).

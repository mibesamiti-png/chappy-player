# PC Link R6B — verification matrix and QA gate

**Status: source/CI candidate, NOT physical device QA.** R6A remains a 4-command, one-QR-one-key prototype. This work adds regression evidence and a private manual checklist, never broad remote control.

## Layers of evidence

| Layer | What can count as passed | What it does not prove |
| --- | --- | --- |
| Python/Dart fixtures | Both calculate each of 8 command-bound SHA-256 nonces identically; distinct from status/file scopes | No Android/Windows TLS interoperability or real PC sound |
| Isolated localhost HTTP | Real P-256 Android/PC proof bytes through actual Python request handlers, fake PC consent and mock executor; denial/replay/expiry | HTTP loopback is not real Wi-Fi, TLS pinning or Windows media routing |
| Quick CI | Flutter analyze/test, offline mini-app manifest permissions [] and no privileged JS, private .chappy artifact | Manual checklist is not a PC action and no real Android phone was touched |
| Windows Preview CI | P-256/HTTP/Windows build with opt-in CMD artifact | Runner output is not a physical Android↔Windows pairing |
| Compatibility APK workflow | ARM64/ARM32/x86-64 Debug APKs built, signed with debug identity, uploaded to private PR artifacts | Not installed, exercised or approved as Stable |
| Physical QA | Tester personally observes same-build PC+Android behavior on owner-controlled LAN | Never infer pass from mock or package presence |

## Deterministic command signatures

- Fixture: `docs/pc-link-r6b-media-vectors.json`; two raw nonces x 4 commands, SHA-256 bytes exactly `CHAPPY-PC-MEDIA-CONTROL-V1` + NUL + ASCII command + NUL + 32 raw nonce bytes.
- Python validates fixture and checks domain independence against R4C status and R5A/R5B file scopes. Flutter parses the same JSON and checks each command. An unrecognized command always fails closed.
- Real hardware tests are not replaced by P-256 validation; tests use deliberately isolated HTTP and a mock Windows key executor.

## 13 case R6B private manual QA (not the 15 core identity cases)

| Case | Expected observation | Starting status |
| --- | --- | --- |
| boot | Android Debug APK and Windows Preview from same Git HEAD are installed/prepared | NOT RUN |
| qr | Fresh media=1 QR/TLS, YES and signed identity acceptance | NOT RUN |
| volume_up | PC system volume increases exactly once | NOT RUN |
| volume_down | PC system volume decreases exactly once | NOT RUN |
| toggle_mute | PC mute toggles exactly once (avoid response retry) | NOT RUN |
| play_pause | Supported active media player changes play/pause once | NOT RUN |
| pc_deny | Refusing/timing out CONTROL prevents key and QR reuse | NOT RUN |
| phone_deny | Refusing Android separate consent prevents key | NOT RUN |
| replay | Second command/proof rejected without extra key | NOT RUN |
| expire | QR/second proof expiration blocks execution | NOT RUN |
| background | Android lock/background/leave screen closes request | NOT RUN |
| offline | Wi-Fi/Windows disconnect is not shown as successful | NOT RUN |
| bridge | private .chappy mini-app cannot reach host P-256/media APIs | NOT RUN |

Independent existing 15 NETLAB-03B identity QA cases remain 0/15 NOT RUN. Never edit those to PASS without device evidence. The 13-case checklist is rendered as an offline, unsigned, zero-permission `local.chappy.pc_control_lab` private Debug .chappy artifact. Only the trusted Android host Network Lab may issue media requests after separate consents. No general keyboard/mouse, remote shell, file, always-on server, or background auto-connect permission.

## Human testing prerequisites

1. Use a trusted LAN, private Windows PC, and Android Debug APK and Windows EXE/CMD from a matching source HEAD. Record commit, build identifiers, Android/Windows versions without secrets.
2. Scan fresh QR-v3 `media=1` using Android Network Lab; PC YES confirms identity, PC CONTROL is separate and shows the exact key, Android confirms again.
3. For each case, get a new QR. NEVER automatically retry a toggle after an uncertain network response. Observe actual Windows behavior and mark PASS/FAIL/BLOCKED only after observing.
4. If debugging, do NOT publish P-256 private keys, full public fingerprints, QR contents, IPs, challenge nonces, device identifiers or raw logs. For revoke/delete scenarios refer to existing NETLAB-03B safety preconditions.
5. Verify the private QA .chappy has `permissions: []`; do not publish it to public Chappy Apps. Signed Stable APK remains untouched.

## Next decisions

Review exact final PR HEAD Quick CI, Windows CI and Android Debug build artifacts. Merge source only if all automated checks pass. This establishes an **implementation and QA harness** gate, not physical QA. A separate owner-operated 13+15 case QA session is required before declaring production readiness.

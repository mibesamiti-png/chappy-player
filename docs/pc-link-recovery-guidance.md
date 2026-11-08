# NETLAB-03B: local recovery guidance

The PC Link pairing screen now shows **次に確認すること** alongside already-classified error and stage codes. Text is a fixed, source-controlled hint chosen using only one recognized `STAGE-*` and one `PAIR-*` code. It never reuses raw exception text and never grants connection permission.

Suggestions point to checking the LAN/PC wait screen, comparing the TLS or PC identity fingerprint, or verifying the Android local key/approval step. They never disable TLS pinning, auto-retry a consumed QR, change identity keys, auto-save trust, or bypass phone approval.

The hints are **not guaranteed root-cause diagnoses**; a stage merely identifies the last operation attempted. They are displayed locally and are not included in the copied code-only report. The existing clipboard privacy behavior is unchanged.

Quick CI checks: `flutter analyze`, `flutter test test/pc_pairing_recovery_guidance_test.dart`, and widget regression in `test/companion_qr_lifecycle_test.dart`. No Debug APK build is requested for this UI-only change; Android↔Windows physical QA remains outstanding.

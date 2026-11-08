# PC Link: safe copyable diagnostic codes

The PC pairing page offers **診断コードだけをコピー** only after a classified QR-v3 pairing failure showing exactly one stage and one error class. The clipboard text contains fixed, allowlisted diagnostic IDs only.

Example clipboard payload:

```text
Chappy Player / PC Link
Stage: STAGE-NET
Error: PAIR-TLS
QR招待・鍵・署名・接続先・端末情報は含みません。
```

The report is built from fixed `PcPairingStage` and `PcPairingFailure` codes. No raw exceptions, URLs, IP addresses, PC names, paths, invitation strings, nonce, keys, signatures, or fingerprints are copied, even if the source error text later contains them. Unrecognized, missing, or ambiguous codes disable the copy control.

This is an explicit foreground clipboard action only; nothing is written to disk, uploaded, or exposed to mini-app JavaScript. The phone's clipboard is managed by the operating system and other apps may be able to read its contents, so do not add sensitive values to this report in future.

Tests: `flutter test test/pc_pairing_diagnostic_report_test.dart test/companion_qr_lifecycle_test.dart`; `flutter analyze && flutter test` in automatic Quick CI. Physical Android and Windows two-device validation remains outstanding. The signed Stable release and Debug APK workflows are unchanged.

# NETLAB-03B-1 — Chappy PC QR invitation bootstrap (prototype)

**Status: source-only QR bootstrap candidate. NOT persistent pairing.**

Related: [Network Lab Issue #56](https://github.com/mibesamiti-png/chappy-player/issues/56) and [one-session TLS identity check](network-lab-session-pairing.md).

## Scope and security boundary

This milestone removes the need to **manually enter a 64-character certificate fingerprint**. It does not create a trusted device record, enable PC commands or collect network traffic.

- Windows owner manually starts `Start-ChappyPairingQR.cmd` (or `ChappyCompanion.exe --start --pair --qr --minutes 10`).
- PC creates a **fresh ephemeral P-256 TLS certificate**, a **fresh random 128-bit invitation ticket**, and an expiry no more than 30 minutes away; the default is **10 minutes**.
- The Windows console presents the certificate's full SHA-256 fingerprint and opens a temporary **QR image** on the PC. The image encodes ONLY the private LAN IPv4, ephemeral port, certificate's full SHA-256 fingerprint, expiry, and one-time ticket.
- On Android, user explicitly taps **Network Lab → PC画面のQRを読み取って接続確認**. The camera starts only from this trusted host screen, never in `.chappy` JavaScript. The QR content is **never treated as a web link**.
- Android validates the exact `chappy-pair://invite?` format, full pin, private IPv4, port, ticket and expiry. The user is shown the PC confirmation page. On confirmation, it uses the full **certificate pin** inside TLS before sending any data, sends the one-time invitation ticket inside TLS, and displays the six-character code.
- The Windows server rejects missing/incorrect/expired tickets **before** consuming the single permitted confirmation attempt. PC owner must additionally compare the six-character code and type `YES`. Both devices close the session after one approved or rejected request.

**QR alone is not permission.** A copied QR may disclose a temporary connection locator, but does not bypass the independent PC console approval. An attacker can spoof mDNS names, so the QR must come from the PC the user physically controls. The six-character code is only a human cross-check; the full certificate pin is what protects the TLS connection. No keys or pairing credentials are persisted on the phone.

## Windows usage

1. Download the artifact named `chappy-companion-windows-preview` from a **successful** [Windows Companion Preview workflow](https://github.com/mibesamiti-png/chappy-player/actions/workflows/build-windows-companion.yml). Extract to a folder and start `Start-ChappyPairingQR.cmd` manually.
2. The command prompt shows the private LAN address and a temporary certificate fingerprint. A QR image should open in the Windows image viewer. The console must remain open during this time.
3. Only use it on a private Wi-Fi/LAN that you administer. Keep the Windows Firewall enabled; allow the app only on the intended Private network if prompted.
4. On a separate compatible Chappy Player Android **development build**, open Network Lab and tap the **QR** button. Scan the image on your actual PC screen. Android 17 targeting SDK 37+ is currently **fail-closed** until the Android service-picker/LAN permission path is completed.
5. Android opens the existing fingerprint-pinned TLS confirmation screen, prefilled from the QR. Tap the confirmation button and compare the six-character code shown by both devices.
6. On the PC, only type `YES` if the codes match exactly and you expected the request. Otherwise decline/stop. No permission continues afterwards.

**Important:** A successful Windows build and Android build do NOT prove on-Wi-Fi QR scanning or TLS pairing. PC Windows Firewall, QR rendering/viewer behavior, camera permission, guest Wi-Fi isolation, clock skew, and Android lifecycle must be tested on real devices before any signed production release.

## QR v1 wire format

Canonical ASCII string (strict field order, no extra fields, total <=256 bytes):

```text
chappy-pair://invite?v=1&ip=192.168.1.77&port=45678&fp=<64 lowercase hex>&exp=<Unix seconds>&ticket=<32 lowercase hex>
```

- Only RFC1918 private IPv4; no DNS names, localhost, IPv6, arbitrary URLs, percent-encoded aliasing, or external web navigation.
- Ticket is 128 bits from `secrets.token_hex(16)` and **never advertised in DNS-SD TXT**.
- Expiry is generated on the PC and validated again on Android before the HTTPS request and on the PC before approval. Clock skew might reject a legitimate QR; there is NO fallback to insecure unpinned TLS.
- The QR request retains `pair-preview-v1` as the envelope but adds mandatory `ticket` field **only when QR mode is enabled**. Existing manual fingerprint mode `--start --pair` remains unchanged.
- PC session itself is one-shot and auto-stops even if nobody connects; after stop, this QR cannot be replayed into a later session because TLS key and ticket both rotate.

## Implementation / test status

- PC: `examples/windows_companion/pairing_invite.py`, updated `pairing_server.py`, `--qr` CLI, `Start-ChappyPairingQR.cmd`, `qrcode[pil]` dependency.
- Android: `lib/core/companion_qr_invite.dart`, `lib/screens/companion_qr_scan_page.dart`, Network Lab button, `CompanionPairingClient` optional ticket/expiry, pairing page pin prefill.
- `tools/test_windows_qr.py`: canonical format, expiry, tampering, wrong/replayed QR ticket, no implicit startup, QR image generation (in Windows CI).
- `test/companion_qr_invite_test.dart`: cross-language vector, parser rejection and no implicit camera navigation.
- CI: exact PR head Windows EXE and Android Flutter/Kotlin tests; NOT equivalent to real device Wi-Fi QA.
- `mobile_scanner: 7.5.0` uses the bundled Android scanner; it increases the Android package size and requests camera permission at runtime only after user enters QR scanning.

## Remaining work (Issue #56)

- Security-reviewed **persistent** mutual device identity/key exchange, Android KeyStore and Windows DPAPI, paired-device list and explicit revoke.
- Privacy-preserving Android 17 target SDK 37+ LAN/service-picker implementation.
- PC-side read-only network metrics with an independent capability approval, **only after** real device trust and revocation are implemented.
- Device QA, compatible signed Android release (only on owner's explicit instruction).

No automatic production APK release or Stable catalog edits are part of this step.

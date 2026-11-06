# Chappy Player — Native capabilities roadmap

Scope: user-selected next features after Chappy Player production v0.3.0. The current version is **not** assumed to support the new APIs. No network server access has been implemented in this branch.

## Phase 1 (this source PR) — file export, motion, haptics

| ID | Feature | Source implementation | Verification | Shipping |
|---|---|---|---|---|
| NATIVE-FILES-01 | Private MP4 export via Android user-selected save-as | Implemented (source): `Chappy.video.export(id)` | Static tests + CI Android build; Android device not verified | Not yet published in signed production player |
| NATIVE-MOTION-01 | Accelerometer, gyroscope, magnetometer one-shot samples | Implemented (source): `Chappy.motion.sample(type)` | Static/JS tests + CI Android build; real sensors not verified | Not yet published |
| NATIVE-HAPTICS-01 | Three predefined short haptic presets | Implemented (source): `Chappy.haptics.play(effect)` | Static/JS tests + CI Android build; physical vibration not verified | Not yet published |
| NATIVE-RECORDER-EXPORT | Chappy Recorder export button | Implemented (source): v0.1.1 candidate, preserving existing stable v0.1.0 | Node UI smoke test; native QA outstanding | Do not publish before compatible signed host |
| NATIVE-DEVICE-LAB | Simple sensor/haptic debug mini-app | Implemented (source), `local.chappy.device_lab` v0.1.0 candidate | Node UI smoke test, .chappy packaging | CI artifact only until device verification |

### Permissions and lifecycle

New .chappy `permissions` are explicit `motion` and `haptics`; camera remains required to export an app's private recordings. The install UI displays the permission labels. Flutter confirms first use of motion and haptics per foreground session and checks the same mini-app's manifest for each request. Native Android calls reject background access. Sensors only register for one sample, automatically unregister on the first sample/timeout/pause, and are capped to 10 reads per second in the Flutter host. Predefined vibration is limited to tick/click/heavy at least 120ms apart on the native host, with no custom arbitrary vibration pattern.

MP4 export never sends private file paths or raw video bytes into JavaScript. It checks app ownership and file canonical paths, launches Android `ACTION_CREATE_DOCUMENT` for the chosen destination, streams bytes in a worker thread, and verifies the output content's size and SHA-256 by reading it back. The original private file is never deleted during export. Export is not a network upload and grants no broad shared-storage permission.

The player's WebView CSP `connect-src 'none'` and local-only server remain unchanged. New APIs do not grant network access.

## Phase 2 — generic file import/export

- **NATIVE-FILES-02 (implemented in source, device QA pending):** `Chappy.files.pickText()` and `Chappy.files.saveText(name, text)` for user-picked UTF-8 documents via Android SAF; initial 64KiB read / 32KiB JS write limits. Uses a dedicated `files` manifest capability and first-use consent. See `docs/native-saf-text-file-io.md`.
- **NATIVE-FILES-02B (implemented in source, Android device QA pending):** Scoped binary asset vault for user-picked ZIP/audio/images/3D data via `Chappy.files.importAsset/listAssets/exportAsset/deleteAsset`; opaque handles, 256MiB/file, 512MiB/app and 32 files/app, streaming SHA-256 import and verified export. See `docs/native-binary-asset-vault.md`.
- **NATIVE-FILES-02C (source prototype, CI/device QA pending):** Optional `Chappy.files.exportCompressedZip(id,preset)` provides lossless, compatible ZIP output with fast/balanced/max DEFLATE levels and actual source-vs-ZIP size comparison; negative savings are shown honestly. Original assets are preserved. See `docs/native-asset-zip-compression.md`.
- NATIVE-FILES-03: per-app project export/import with manifest version and checksum; clear error/recovery behavior, no silent overwrite, no bulk private storage exposure.
- NATIVE-FILES-04: optional directory export and batch backup with Android SAF `ACTION_OPEN_DOCUMENT_TREE`, only for user-chosen directories and explicit selection. Verify all files and show progress.

## Phase 3 — network and file transfers

- **NATIVE-NET-01 (source candidate; CI and device QA pending):** Per-mini-app `Chappy.network.request/connect/send/poll/close` for bounded HTTPS GET/POST and WSS text messaging. Requires declared `network` permission, explicit per-origin user consent, verified TLS with public-IP-pinned DNS, rate/message limits and shutdown on background. Keeps WebView remote `connect-src` disabled. No automatic reconnect or credential storage yet. See `docs/game-server-transport.md`.
- NATIVE-TRANSFER-01: SFTP (SSH) and/or FTPS file transfer, configured by the user for a chosen server. Prefer secure protocols; **plain FTP without encryption is not enabled** because it exposes credentials and file contents. Never embed passwords in public mini-apps or expose stored credentials to untrusted JS. Android KeyStore for credentials, explicit uploads, host key pinning for SFTP.
- NATIVE-LAN-01: paired, authenticated Wi-Fi/LAN device connectivity and discovery for later smartphone↔PC integration. Require explicit pairing and mutual authorization, with user-friendly revoke.
- **NATIVE-GAME-01 (protocol demo only):** Chappy Game Server Lab v0.1.0 preview + optional loopback-only Python ping/join/state room server (source only). Real multiplayer service, server-authoritative game simulation, user authentication, latency metrics, reconnection and production hosting remain **not implemented**. Remote data never executes native device actions.

## Phase 4 — PC companion and remote operations (deferred)

- NATIVE-PC-01: optional Windows companion app to control PC functions after a secure pairing QR/code and explicit user confirmation; no unrestricted remote command execution or hidden remote access. Start with limited controls (play/pause, next, volume) before mouse/keyboard. No implementation in this release.

## Release gates

1. CI tests: Flutter analyze/test, native permission/lifecycle source guards, JavaScript simulation, .chappy package validation, Kotlin/Gradle debug APK compilation.
2. Android physical-device QA: private video export to different document providers; cancel and low-storage cases; sensor availability and no background reads; haptic duration/rate limiting.
3. Publish signed host version higher than v0.3.0 using existing permanent production key only after QA. Do **not** replace production signing secrets, uninstall the signed app, or delete private recordings.
4. Only then bump and publish stable Chappy Recorder candidate with video export, and optionally surface Device Lab in Debug for additional testers.

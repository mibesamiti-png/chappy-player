# Mini-app document import/export — SAF text API

Status: Phase 2 implementation candidate, not yet distributed in a signed Chappy Player build. Android real-device validation pending. Previous Stable Chappy Recorder v0.1.0 remains unchanged.

## Why this API exists

Mini-apps often need to import/export presets, notes, scene descriptions, MIDI settings and JSON. Do **not** grant a .chappy app arbitrary read/write access to shared phone storage, and do not expose private Chappy Player paths. Android's Storage Access Framework (SAF) lets the user explicitly choose each source/destination.

- New per-app manifest capability: `permissions: ["files"]`, with a clear install-time label and a one-time foreground-session confirmation.
- `Chappy.files.pickText()`: prompts Android's `ACTION_OPEN_DOCUMENT`; the mini-app receives `{ status: "selected", fileName, text, sizeBytes }` for one chosen UTF-8 document or `{ status: "cancelled" }`. Inputs are limited to **64 KiB**. Non-UTF-8 and larger files fail without reading further.
- `Chappy.files.saveText(name, text)`: permits only safe filenames ending in `.txt`, `.json`, `.csv`, or `.md`. The JS side limits UTF-8 payloads to **32 KiB** (keeps the JSON bridge under its 256 KiB request bound); the native side also validates a 64 KiB maximum. The user picks the destination using `ACTION_CREATE_DOCUMENT`. Source content is written in a worker thread; the destination is **read back and SHA-256 compared** before reporting `{ status: "saved", sizeBytes }`.
- File picker callbacks are single-active-request only. Errors and cancellations are surfaced explicitly; the system file picker is never bypassed.
- There is **no FTP, network, raw filesystem path access, bulk backup or binary transfer** in this phase. The WebView's CSP remains `connect-src 'none'`.
- User-selected SAF access does not require any broad storage permission.

## User-facing test mini-app

`sample_apps/file_lab/index.html` packages as `local.chappy.file_lab` 0.1.0 (permission `files`). It can open a text/JSON file, edit content, save through Android's picker and temporarily store a local draft using existing `Chappy.storage`. It is for controlled testing; it is not yet in the public Stable/Debug catalog.

## Release safety gates

- `python3 tools/test_android_media_manifest.py`: ensures new NativeMiniAppDocuments host is included by Android generator twice without duplication.
- `python3 tools/test_native_documents_contract.py`: validates foreground gating, per-app capability consent, pick/save SAF intents, bounded UTF-8, readback SHA-256, no WebView network capability.
- `node tools/test_file_lab.js`, `node tools/test_bootstrap.js`, `python3 tools/test_chappy_package_tools.py`: exercise UI, JS protocol and manifest/package builder.
- Flutter analyze/test and Android Debug APK Kotlin build must pass on exact PR SHA.
- After code CI is green, verify Android 14 device picker (open valid JSON, cancel, invalid UTF-8, oversized file, safe save, failed content provider write, fallback display name, app background and private-data isolation). No automatic formal signature or published mini-app update before device QA.
- Later: larger media/data requires streamed handles and per-app quotas instead of increasing the JavaScript bridge's payload cap.

## Relationship to requested roadmap

1. File handling: first native private MP4 export (PR #40) then bounded SAF text documents (this PR), then batch/large file backup.
2. Sensor and haptics: PR #40; complete device QA before permanent production release.
3. Secure file transfer (SFTP/FTPS) and online multiplayer HTTPS/WSS; user-configured endpoints, no plain FTP credentials or unrestricted commands.
4. Explicitly paired Windows PC companion: deferred.

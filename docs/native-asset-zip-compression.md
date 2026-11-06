# NATIVE-FILES-03 — Optional, lossless ZIP compression export

**Status:** implemented as a source-code candidate. Android CI and device QA required. Does **not** change installed Chappy Player v0.3.0 or Stable mini-app catalog.

## Motivation

After building a scoped asset vault and reliable transfer cancellation, give mini-apps an optional way to export one stored file as a standards-compliant ZIP and *measure* whether compression helps. This is a **standard DEFLATE implementation**, not a new algorithm or a claim of exceptional compression ratios.

## User experience

Chappy File Lab v0.2.2 candidate: import a file, then choose **高速 / 標準 / 最大圧縮** and press **可逆ZIPで保存**. Android shows its normal save destination picker. The original file stays in the private vault; the output ZIP is readable by ordinary ZIP utilities.

ZIP contains:

- `files/<sanitized-original-name>` — original bytes, compressed losslessly.
- `manifest.json` — schema version, type, original filename/MIME/byte count, SHA-256 and chosen compression level.

App-level JS API:

`Chappy.files.exportCompressedZip(assetId, preset = "balanced")`

`preset` is one of `fast` (DEFLATE level 1), `balanced` (level 6), `max` (level 9). Native accepts only these exact values through a Flutter-vetted integer mapping.

Successful response:

```json
{
  "status": "saved",
  "originalBytes": 262144,
  "zipBytes": 2103,
  "savedBytes": 260041,
  "percentSmaller": 99.1978,
  "compressionLevel": 6,
  "sha256": "<SHA-256 of saved ZIP>"
}
```

Numbers above illustrate the response shape only; **actual ratios are calculated from the selected file**. If an already-compressed MP3, JPEG, PNG or ZIP grows after wrapping, `savedBytes` and `percentSmaller` are **negative**. UI describes that as an increase, not a saving.

If the user cancels, the response is `{"status":"cancelled"}`. On readback failure, cancel during copying/verification, or source checksum mismatch, the save is *not* reported as successful; the host attempts to delete a partial destination. Some content providers may deny deletion.

## Integrity and boundaries

- Android streaming uses a 64KiB buffer; binary data never enters the WebView/JavaScript bridge.
- Before returning success, SHA-256 checks the original vault file against its private metadata, and independently reads back/hashes the **actual saved ZIP** from the Android document provider. ZIP CRCs are supplied by `ZipOutputStream`.
- App ID is inserted by Flutter and validated by Android; the mini-app cannot specify arbitrary private paths or act on another app's files.
- Requires the existing `files` manifest capability, active foreground mini-app, and first-use user consent. Saving uses Android `ACTION_CREATE_DOCUMENT`; no broad storage permissions.
- Explicit original file limit remains 256MiB, app quota remains 512MiB and 32 items. The compressed ZIP is exported to a user-selected document, not silently installed as a second vault item.
- Existing `transferStatus()` and `cancelTransfer()` cover ZIP copy and readback. After the `finalizing` phase, cancelling cannot roll back an already-saved archive. System document picker cancellation is controlled by the system UI.
- ZIP export is **not encrypted**, not automatic, does not delete originals and does not access the network. Use trusted storage if the file is private.

## Release and test gates

`tools/test_asset_zip_compression.py` verifies the native API contract and runs independent ZIP/DEFLATE reference fixtures for easily compressed text-like bytes and incompressible pseudorandom bytes, requiring exact byte-for-byte decompression and honest negative ratio when larger. Also run `tools/test_native_asset_vault.py`, `tools/test_file_lab.js`, `tools/test_bootstrap.js`, Flutter analyze/test and Android Kotlin debug APK build.

**Real Android QA pending:** compare levels 1/6/9 for actual Blender/PNG/MP3/ZIP/text assets; validate ZIP in external extractor, manifest/hash, checksum on failed cloud provider writes, cancellation, low storage and provider readback; confirm existing Stable Recorder and personal videos untouched.

## Roadmap separation

This is the file-vault export path, **not** a compression engine for GBS Player or KIZAMI Lab; it does not support differential compression, Zstandard or multi-file archive optimization. Issue #43 keeps future bulk-file backup and restore, while issue #42 keeps SFTP/Wi-Fi/online game-server networking deferred until user-visible device QA.

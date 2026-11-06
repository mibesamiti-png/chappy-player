# NATIVE-FILES-02B — Scoped binary file vault

**State:** source implementation candidate; Flutter/Android CI and physical-device QA are required before a signed release. Current production Chappy Player v0.3.0 and Stable Chappy Recorder v0.1.0 are unchanged.

## Overview

Mini-apps may need to work with ZIP archives, WAV/FLAC/MP3 audio, PNG images, Blender files and other binary documents much larger than the existing 64KiB UTF-8 text picker. These files **must not pass through the HTML/JavaScript message bridge**.

The Android native host now provides a *private asset vault* for each installed mini-app. Every mini-app's files are isolated beneath its own app ID: `filesDir/chappy_private_assets/<app-id>/`. Flutter supplies this owner ID; untrusted mini-app JavaScript cannot select a different owner's folder. The data remains inside Chappy Player and is not visible in the device's shared Gallery or file browser.

## JS API

| Method | Result | Behavior |
|---|---|---|
| `Chappy.files.importAsset()` | `{status:"imported",file:{id,name,mime,sizeBytes,sha256,createdMs}}` or `{status:"cancelled"}` | Android `ACTION_OPEN_DOCUMENT`; copy user-chosen binary file into private vault, stream in 64KiB chunks, compute SHA-256 |
| `Chappy.files.listAssets()` | Array of metadata objects | Lists only the active mini-app's verified private records |
| `Chappy.files.exportAsset(id)` | `{status:"saved",sizeBytes,sha256}` or `{status:"cancelled"}` | Android `ACTION_CREATE_DOCUMENT`; save selected private file and read back from the actual destination, verify SHA-256 |
| `Chappy.files.deleteAsset(id)` | Boolean | Show native confirmation, delete only the exact private item belonging to this mini-app |

The `id` is an opaque, randomly generated 32-character hex handle. No app-private path, Android `content://` URI, or binary payload is exposed to JavaScript. `Chappy.files.pickText()` and `saveText()` continue to work independently.

## Optional, measured ZIP compression export (source update)

`Chappy.files.exportCompressedZip(id, preset)` exports **one** private asset as a lossless DEFLATE ZIP using Android's destination picker. Presets are `fast`, `balanced` (default) and `max` (ZIP level 1/6/9). The ZIP includes the original file and a JSON checksum manifest; the host checks source SHA-256 and hashes the saved destination after readback.

The result reports actual `originalBytes`, `zipBytes`, `savedBytes` and `percentSmaller`. **Negative values explicitly mean that the ZIP is larger**, e.g. for MP3, JPEG or an existing ZIP. The original vault item remains untouched and the archive is not encrypted. See `docs/native-asset-zip-compression.md`.

## Transfer progress and cancellation (source update)

- `Chappy.files.transferStatus()` reports only the active caller mini-app's current operation: `{active,phase,bytesDone,totalBytes,cancelable,cancelRequested}`. A total of `-1` means the Android document provider did not disclose its file size. No filename, destination URI, path or raw file contents are sent to JavaScript.
- `Chappy.files.cancelTransfer()` asks Android to stop the current caller's transfer; returns `false` if no cancellable transfer is underway. Only the **copying** and **verifying** phases accept cancellation. The Android file picker itself must be closed/cancelled with its own system UI. Once the private-file commit enters **finalizing**, cancellation is disabled to prevent success after a rollback of completed content.
- Import checks the cancellation flag at every streamed chunk and just before committing the private item; export checks during copy and SHA-256 readback. Cancellation returns `{status:"cancelled"}`. Failed/aborted imports remove partial data; failed/aborted exports attempt to remove incomplete documents. Some providers disallow deletion, so a partial file may still remain outside the app.
- The File Lab interface polls status every 350ms while an import/export is pending, shows bytes transferred and an optional percent when total length is known, and has a **転送をキャンセル** button.
- On the next idle vault listing or import, the Android host removes **only 24-hour-old unfinished `[hex].part` files** under that same mini-app's private directory. Completed `.blob` and `.json` records are never automatically removed.
- These APIs do **not** yet include a byte-stream handle that JavaScript can read, upload, edit or process; they manage a private vault copy through explicit Android pickers.

## Permission boundaries

- The mini-app manifest must declare `permissions:["files"]`. The installer displays the capability label; Flutter additionally confirms first use **once per foreground session**.
- Every call to Android passes the current `widget.app.id` from the trusted Flutter runtime; the Android service validates a strict package-ID format, file ID and canonical per-app directory.
- Imports and exports always use a system picker. File deletion requires a second native confirmation. No external-storage-wide permission is granted.
- The local WebView Content Security Policy still blocks remote `connect-src`. **No FTP, Wi-Fi server access or upload capability exists in this API.**
- During a transfer, another vault operation is rejected. On import failure, temporary data is removed; the original selected file is never modified. Export failures attempt to remove a partial destination and are clearly reported.

## Quotas and expected behavior

- Max **256MiB** per file, **512MiB** total stored bytes per mini-app, **32 files** per mini-app.
- Empty files and entries beyond quotas are rejected. Imported records store normalized display names and MIME types, exact byte size, timestamp and SHA-256. File names are rendered as text, not HTML.
- Importing a file creates a **new private copy**, not a live link to the original; imports are not deduplicated. Re-importing consumes additional quota.
- Export **never silently overwrites a vault item**. Saving outside the vault uses Android's standard file picker. Some document providers cannot be read back for SHA-256 verification; in that case the export reports an error instead of claiming success.
- **Uninstalling Chappy Player or clearing app data destroys these vault copies.** Export anything important before uninstall.
- This first stage does not implement automatic backup, directory sync, arbitrary JS binary read/write, incremental chunk APIs, or a restoration manifest for the vault. The existing camera-video ZIP exporter is a separate feature.
- Large content-provider operations may take time and use additional internal space. 24-hour-old partial import files are cleaned up opportunistically; a force-kill after a body is committed but before its metadata is saved could still leave an orphan. Safely reclaiming orphaned completed bodies is a separate future maintenance task; no automatic deletion of user data has been enabled.

## QA gates

- `python3 tools/test_native_asset_vault.py`: native foreground/manifest access, owner+handle validation, quota and 64KiB stream/checksum contract, independent reference fixture.
- `node tools/test_file_lab.js`: interactive import/list/export/delete, alongside existing text save/open and local draft.
- `node tools/test_bootstrap.js`: JavaScript protocol, promises and metadata-only results.
- `python3 tools/test_android_media_manifest.py`: includes the Kotlin helper in Android project template, checks patcher idempotence.
- Flutter analyze/test, Kotlin/Gradle debug APK compilation and a successful exact-head GitHub Actions run are required before merge.
- Physical-device verification needed: files in Downloads and Google Drive providers; 0B, 256MiB boundary, 257MiB rejection; 33rd file, 512MiB quota; export readback failure; cancel, app background, activity recreation, low storage, data isolation between two mini-apps, app reopen and persistence across player update.

## Relation to later server/game plans

The private vault provides a bounded, validated place to stage file data for eventual SFTP/FTPS transfers or HTTPS/WebSocket game assets. **Those network interfaces are not implemented here** and will need separate per-host authorization, credentials, TLS, data quotas and first-use confirmation. PC remote control remains deferred.

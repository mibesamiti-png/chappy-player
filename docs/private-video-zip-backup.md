# RECORDER-ZIP-01 — Verified private MP4 batch backup

Status: **implemented in source branch; CI and real-device QA pending**. Current public Chappy Player v0.3.0 and Stable Chappy Recorder v0.1.0 are unchanged. This feature is an export, **not a restore** feature.

## User flow

In a compatible new Chappy Recorder mini-app, tap **プライベート動画を表示** then **非公開動画をまとめてZIP保存**. The Android host enumerates the mini-app's **own completed private MP4s**, not other mini-apps' videos, and displays a confirmation containing count and approximate MiB. On approval, Android's `ACTION_CREATE_DOCUMENT` asks the user to choose the destination and ZIP filename. A cancellation leaves all originals intact and reports `cancelled`.

The app creates a ZIP in a worker thread. It stores MP4 files under `videos/Chappy_<timestamp>.mp4` using no additional compression (MP4 files are already compressed) and a `manifest.json` with `schemaVersion: 1`, `type: chappy-private-video-backup`, `ownerId`, timestamp, `fileCount` and each video's filename, exact byte length and SHA-256 digest.

**Integrity:** the output stream is SHA-256 hashed while writing, then the actual selected provider's saved ZIP is read back and hashed again before success is reported. Failures return an error and the host attempts to delete the incomplete destination. Providers may deny deletion; the user is warned a partial file could remain. The original private recordings are never deleted.

## Explicit limits and access boundaries

- Exactly one owner (`.chappy` package ID) per request. Flutter requires the caller's existing `camera` manifest capability and foreground route, and native Android independently validates the owner and idle recording state.
- All matching completed videos are enumerated; unlike the UI's last-100 list, the export fails rather than silently skipping older videos.
- Maximum **100 MP4 files, total source size 4GiB**, with individual source up to 1GiB. If empty, oversized, or too many, refuse before displaying a misleading success.
- No raw paths, video contents, or document provider URI are sent to JavaScript. The one-bit saved/cancelled result includes file count, ZIP size and ZIP SHA-256 when saved.
- No automatic upload, FTP, network permission, public Gallery exposure, or broad filesystem access. The destination comes only from the standard Android picker.
- This is a large streaming backup: providers must permit readback and sufficient free storage. Network-backed document providers may take time. Do not quit the app mid-export.
- At present ZIP restore/import, automatic backups, multi-mini-app archives and backups larger than the limits are **not** implemented. Do not uninstall Chappy Player until manually verifying your copy.

## APIs and QA

- `Chappy.video.backupZip()` sends `video.backupZip` to Flutter, which calls Android `backupPrivateVideosZip` with the active mini-app owner's ID.
- Native `privateBackupSources(owner)` validates every candidate's real/canonical private path, recorded filename, idle state and total file limits.
- `tools/test_private_video_zip_backup.py`: static privacy, path, manifest and integrity contract tests.
- `tools/test_chappy_recorder.js`, `tools/test_bootstrap.js`: UI and bridge behavior.
- `tools/test_android_media_manifest.py`: generated native Kotlin class inclusion and idempotent patch.
- Android Kotlin compile via normal PR CI and release signing test gate. **Actual device test still needed:** saving one and many videos, 0-byte provider, cancelled picker, insufficient storage, corrupted/incomplete target, 101 files, app background, replay ZIP extraction and checksum validation in an independent ZIP tool.

## Follow-on task

Issue #43 remains the larger goal: binary streaming import/export for arbitrary mini-app files and backup restoration with conflict handling. The planned SFTP/Wi-Fi/game server transport is later, tracked under #42.

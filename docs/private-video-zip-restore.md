# RECORDER-ZIP-02 — Verified private-video ZIP restore

**Status: source implementation; Android CI and device tests required.** No signed production player or Stable mini-app is published by this work. Current signed v0.3.0 and Stable Chappy Recorder v0.1.0 remain unchanged.

## User flow

Chappy Recorder → **プライベート動画を表示** → **バックアップZIPから復元**. Android's system file picker lets the user explicitly select one ZIP. On receipt the host verifies the archive **before touching final private MP4 filenames**.

The native verifier requires:

- Manifest `schemaVersion = 1`, `type = chappy-private-video-backup`, `ownerId` exactly matching the calling mini-app's ID; video count matches the real ZIP entries.
- Strictly named `videos/Chappy_[0-9_]+.mp4` entries plus exactly one `manifest.json`, no extra directories, traversal paths, or duplicate names.
- Maximum 100 videos, **1GiB each / 4GiB total extracted**, with a 256KiB JSON manifest. ZIP decompression streams into a temporary directory inside the caller's private video directory. No video payload is sent to JavaScript.
- Streaming SHA-256, size and ZIP CRC checks for every entry; all entries must match the complete manifest. Corrupt, mismatched, cross-owner and oversize archives fail before any final file is created.

After complete verification Android shows the number of new videos and the number already present. **Existing identical recordings are skipped. A same-name recording with different contents rejects the entire restore. No overwrites.**

The user then explicitly confirms or cancels. Confirming moves staged video files to their final private names. On error the host attempts to roll back files created by this attempt, preserving old recordings. Temporary stage files are cleared. The mini-app refreshes the private video list after success.

## API and permissions

- `Chappy.video.restoreZip()` → Flutter `video.restoreZip` → native `restorePrivateVideosZip`. JavaScript gets only `{status:"restored", restored, skipped, total}` or a cancellation/error; no file paths, URIs, secrets or contents.
- Requires the calling mini-app's **camera** capability and foreground route. The native player locks recording, opening, deletion, single-video export and ZIP backup while a restore is in progress, including when the Android picker temporarily pauses the app.
- **No storage-wide permissions**, unrequested imports, automatic uploads, network connections, or silent restore. A malicious mini-app cannot request another mini-app's backup because the caller owner is inserted by Flutter, and the ZIP itself must declare that owner.

## Limitations and next steps

- This initial build imports only ZIPs produced by Chappy Player's private MP4 backup format. Arbitrary ZIPs, changed archives and other app owners are rejected.
- Staging may require as much *extra free internal storage* as the videos being restored. An insufficient-storage or device-kill incident can leave hidden temporary files; these are not listed as completed videos. A future maintenance feature can safely clear abandoned temp directories after confirming no operation is running.
- Restore is not yet available for generic mini-app project data, settings, 3D assets or videos exported directly to Gallery.
- Android real-device testing required: one/many files, duplicates, same-name conflict, wrong owner, ZIP path traversal, decompression bomb, corrupted SHA, cancel during picker/confirmation, low storage, activity recreation, 4GiB boundary, and restoration across versions.
- Future file import/export/PC/SFTP and multiplayer transport remain separately tracked in issues #43 and #42.

## Automated checks

`tools/test_private_video_zip_restore.py` checks native consent/path/security invariants and compatible valid/invalid fixture ZIPs. `tools/test_chappy_recorder.js` and `tools/test_bootstrap.js` simulate UI + JS bridge. `tools/test_android_media_manifest.py` checks inclusion in the Android patcher. PR CI must also complete Flutter analyze/test and native Kotlin Gradle debug APK compilation. Unit/static smoke tests do not replace actual device QA.

**Release gate:** no release/Stable catalog bump until compatible signed production host with this API is deliberately published after device testing; never uninstall the current signed player just to try this feature.

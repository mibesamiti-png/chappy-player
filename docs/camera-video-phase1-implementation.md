# Camera video recording — Phase 1 implementation and QA

Updated 2026-11-06. This is a **debug-stage implementation**, not shipped in the signed v0.2.4-b10 APK.

## Implemented in this branch (CAMREC-01/02/03/04/09/10/11 — partial)

- Native Android CameraX Recorder/VideoCapture generates MP4 files with selectable front/back camera, 720p/1080p preferred quality and optional audio.
- Each start is gated by the mini-app `camera` manifest declaration (plus `microphone` if audio), a fresh Chappy Player confirmation dialog, Android runtime permission and an active foreground screen.
- Standard output is `filesDir/chappy_private_videos/<appId>/`. Files are not indexed by Android's shared MediaStore and can be listed/played only by the owning mini-app via a host-controlled native VideoView.
- Opt-in gallery output writes through MediaStore to `Movies/ChappyPlayer` on Android 10+. The app explicitly tells users that other apps can see this video.
- The JavaScript bridge only exposes `Chappy.video.start/status/stop/dark/list/open` and metadata. It **never** returns private file paths, raw frames or audio.
- Black-screen mode dims this Activity's brightness and overlays a visible recording indicator, recovery button and Stop button. The physical display stays **ON**; OS privacy indicator is not suppressed.
- CameraX is bound to a foreground Android lifecycle owner; recording is stopped when the Activity pauses or the user leaves the mini-app. No camera background foreground service is registered.
- MP4s are first written to a `.pending` file and made visible in the private library only after CameraX finalization succeeds.
- The debug Media Lab `v0.1.4` adds camera/audio/storage options and a private video library UI. Earlier controls for still photos and native mic diagnostics are kept.

## Not implemented / requires further work

- CAMREC-06/07: background recording after locking screen or switching app, with camera/microphone foreground service and persistent stop notification.
- CAMREC-11: exporting selected private MP4s to a chosen folder. Native in-app playback exists; **export is not yet implemented**.
- CAMREC-12: dedicated large-video backup/export flow and deletion protection. Android app data removal or uninstall deletes private MP4s; current JSON backup excludes them.
- Safe per-video deletion, free-space warning UI and long-recording performance monitoring beyond the CameraX 1GiB file size limit are pending.
- CameraX output uses only video capture use case; WebView camera preview is released before starting native capture. A simultaneous preview requires a native Preview use case later.
- CameraX quality selector chooses a lower/higher supported quality if the preferred option is unavailable. Exact resolution requires hardware inspection.
- Native `VideoView` is a basic playback proof of concept; Android device UX is not yet verified.

## Verification gates

1. GitHub Actions on the **exact PR SHA**: `flutter analyze`, `flutter test`, Android debug Gradle/Kotlin build, native permission static checks, Node Media Lab syntax/behavior and package validation.
2. Install **debug APK only on a device that can accept its debug signature**. Do not uninstall the existing signed v0.2.4 to test; that would erase app data. Prefer a separate test device or build variant/applicationId for isolated QA.
3. On an Android 14 test device: approve camera/audio, record 10–20 seconds into private storage, confirm file in the in-app list, native playback works and the standard gallery/Google Photos do not show the video.
4. Repeat using gallery storage, confirm a user-visible MP4 appears in Photos/Gallery.
5. In active recording, tap dark-screen; confirm the brightness decreases, UI can recover and stop recording. On activity background or screen off, capture must stop and brightness return. Review finalization and incomplete-file behavior.
6. Check permission refusal, audio disabled, camera swap, resolution fallbacks, Android camera/mic privacy indicators and preservation of existing .chappy/ASMR/memo data.

## Privacy and release constraints

No hidden camera operation, covert background capture, disable-OS-indicator feature, automatic post-boot recording or network upload. Existing GitHub signed-release workflow is manually triggered only. Wait for successful CI **and physical QA** before releasing this feature to the installed signed application.

## Debug v0.1.5: dark-screen hardware keys and private video deletion (pending QA)

- Enter dark mode from an already user-approved CameraX recording. The black overlay shows **only an 8px upper-right status dot** (red while recording/finalizing; green after the saved file reaches idle). Its 64px invisible touch target restores the normal interface on double tap. There is no custom recording text over the dark overlay. Android privacy indicators remain visible.
- While the app stays foreground and dark: **volume down** requests a stop; **volume up**, after an earlier successful capture, reuses that capture's camera/quality/audio/storage options to request a *new* session, with a fresh consent dialog. For readability the overlay/brightness is temporarily restored while asking permission. The dark overlay returns afterwards, including when the user cancels; recording never restarts silently.
- System volume keys behave normally outside dark mode. Android lock screen, background and activity pause still stop the recording and restore brightness. Hardware shortcut interception is device-dependent and needs Xiaomi Android 14 testing.
- Private video list has **play** and **delete**. Every deletion requires a host-controlled, explicit confirmation, validates owning mini-app ID and a basename-only MP4 ID, allows deletion only when recorder is idle, and cannot be undone. MediaStore/gallery videos are not included in this private delete API.
- Media Lab Debug version is **v0.1.5**, not a production APK release. Verify CI on the exact branch head, ensure `Chappy Player Debug` installs alongside the existing signed v0.2.4, then test physical volume buttons, 10-second capture, file finalization, green dot, double-tap recovery, private playback and confirmed deletion. Do not uninstall existing production app or publish a signed release without explicit instruction.

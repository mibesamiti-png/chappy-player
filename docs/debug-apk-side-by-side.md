# Side-by-side Chappy Player Debug APK

Created 2026-11-06. Experimental camera video verification often needs an unsigned-for-release Android debug APK. The existing production Chappy Player is signed with a fixed **different** certificate; neither app should need to be removed.

## Debug-only change

- `.github/workflows/build-android.yml` runs `tools/prepare_debug_variant.py` **only before the debug APK build**.
- Debug application ID becomes `dev.chappy.chappy_player.debug`; launcher title becomes `Chappy Player Debug`. Kotlin/Dart package import paths are not changed.
- Release application ID stays `dev.chappy.chappy_player`; the separate manual `publish-signed-apks.yml` workflow never invokes the helper.
- Android app storage is isolated by package ID. A new Debug installation cannot overwrite or delete the existing production app's notes, mini-apps, or private camera recordings.
- Updates from the production update.json should be rejected in the Debug variant because its Android package name differs. Do **not** expect in-app production updates in Debug.

## How to test the camera prototype safely

1. Download the `chappy-player-debug-apk` ZIP artifact from a **successful** `Build Android APK` workflow on the relevant commit. Unzip and install `app-debug.apk`. Do not uninstall the currently signed production application.
2. Confirm there are now **two separate launcher icons**: `Chappy Player Debug` and the existing `Chappy Player`.
3. Also download the `chappy-media-probe` artifact from the same workflow, and import `media-probe.chappy` into the Debug app (Media Lab v0.1.4).
4. In Debug, choose the native video recording camera, desired 720/1080 quality and private storage. Allow Camera and optionally Microphone; test recording, stopping, dark mode recovery and in-app playback. Then verify Gallery/Google Photos does not index private MP4s.
5. Uninstall **only** `Chappy Player Debug` when done; doing so deletes Debug-only private recordings. It does not touch the production app.

## Quality and signing boundary

`tools/test_prepare_debug_variant.py` verifies Android Kotlin and Groovy build scripts are patched idempotently. The CI must compile an APK on this exact PR commit and validate that production signing workflow and source package identity remain unchanged.

There is no promise of Android physical-device correctness from CI alone. No signed production release is created by this PR.

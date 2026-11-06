# Side-by-side Chappy Player Debug APK

Created 2026-11-06. Experimental camera video verification often needs an unsigned-for-release Android debug APK. The existing production Chappy Player is signed with a fixed **different** certificate; neither app should need to be removed.

## Debug-only change

- `.github/workflows/build-android.yml` runs `tools/prepare_debug_variant.py` **only before the debug APK build**.
- Debug application ID becomes `dev.chappy.chappy_player.debug`; launcher title becomes `Chappy Player Debug`. Kotlin/Dart package import paths are not changed.
- Release application ID stays `dev.chappy.chappy_player`; the separate manual `publish-signed-apks.yml` workflow never invokes the helper.
- Android app storage is isolated by package ID. A new Debug installation cannot overwrite or delete the existing production app's notes, mini-apps, or private camera recordings.
- Updates from the production update.json should be rejected in the Debug variant because its Android package name differs. Do **not** expect in-app production updates in Debug.

## Debug-only first-launch mini-app library (8 offline examples)

Starting with the debug APK that includes this feature, the **first launch**
of `Chappy Player Debug` installs eight repository-owned `.chappy` examples
into the **debug package's separate library**. No GitHub catalog connection or
separate ZIP import is required. This is a debugging convenience, not a
production catalog publication.

| Built-in debug sample | Declared permissions | Useful test |
| --- | --- | --- |
| メモ帳 | none | Save/edit a note and verify private data persists |
| Chappy Media Lab | camera, microphone | Video/microphone/camera diagnostics |
| Chappy Recorder | camera, microphone | Local private recordings and video library |
| Chappy Device Lab | motion, haptics | Accelerometer/gyroscope and vibration |
| Chappy File Lab | files | User-selected documents and asset import |
| Chappy Game Server Lab | network, motion, haptics | Optional HTTPS/WSS connection to a user-supplied server |
| Chappy Touch Lab | none | Multitouch, pointer events, gesture trails |
| Chappy Color Lab | none | RGB sliders, rendering, clipboard test |

No sample starts a camera, microphone, network connection, or remote command
just because it is installed. The recorder and other permissioned apps still
need runtime Android permissions and user action where appropriate. Use only
your own test data and servers.

**Data protection**: Seeds run exactly once per seed-version in the
`dev.chappy.chappy_player.debug` data sandbox. Already-installed app IDs are
never replaced or downgraded, and private app data is not touched. If you
delete a seed app later, subsequent launches do **not** silently reinstall it.
An incomplete first run can retry missing apps without overwriting successes.
Signed production APKs do not execute the seeder or bundle the extra assets.

Implementation: `tools/prepare_debug_samples.py` creates SHA-256 checked
ZIP archives in ignored `debug_sample_assets/` and adds that asset directory
to pubspec **only after the debug test stage, before the debug build**.
`lib/core/debug_sample_seeder.dart` verifies manifest, ZIP and checksums
again before the first installation.

## How to test the camera prototype safely

1. Download the `chappy-player-debug-apk` ZIP artifact from a **successful** `Build Android APK` workflow on the relevant commit. Unzip and install `app-debug.apk`. Do not uninstall the currently signed production application.
2. Confirm there are now **two separate launcher icons**: `Chappy Player Debug` and the existing `Chappy Player`.
3. On the new Debug APK, Media Lab and the other seven demos should already appear in **MY APPS** after first launch. For older Debug APK builds without this feature, import `media-probe.chappy` from the workflow artifact manually.
4. In Debug, choose the native video recording camera, desired 720/1080 quality and private storage. Allow Camera and optionally Microphone; test recording, stopping, dark mode recovery and in-app playback. Then verify Gallery/Google Photos does not index private MP4s.
5. Uninstall **only** `Chappy Player Debug` when done; doing so deletes Debug-only private recordings. It does not touch the production app.

## Quality and signing boundary

`tools/test_prepare_debug_variant.py` verifies Android Kotlin and Groovy build scripts are patched idempotently. The CI must compile an APK on this exact PR commit and validate that production signing workflow and source package identity remain unchanged.

There is no promise of Android physical-device correctness from CI alone. No signed production release is created by this PR.

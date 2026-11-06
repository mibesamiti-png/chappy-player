# Side-by-side Chappy Player Debug APK

Created 2026-11-06. Experimental camera video verification often needs an unsigned-for-release Android debug APK. The existing production Chappy Player is signed with a fixed **different** certificate; neither app should need to be removed.

## Debug-only change

- `.github/workflows/build-android.yml` runs `tools/prepare_debug_variant.py` **only before the debug APK build**.
- Debug application ID becomes `dev.chappy.chappy_player.debug`; launcher title becomes `Chappy Player Debug`. Kotlin/Dart package import paths are not changed.
- Release application ID stays `dev.chappy.chappy_player`; the separate manual `publish-signed-apks.yml` workflow never invokes the helper.
- Android app storage is isolated by package ID. A new Debug installation cannot overwrite or delete the existing production app's notes, mini-apps, or private camera recordings.
- Updates from the production update.json should be rejected in the Debug variant because its Android package name differs. Do **not** expect in-app production updates in Debug.

## Eight mini-apps in the *public* Debug catalog

The user-selected samples live in the public
[Chappy Apps Debug catalog](https://github.com/mibesamiti-png/chappy-apps/blob/main/catalog.json).
They are **not automatically installed** when a Debug APK opens, and the
Debug APK need not be rebuilt simply to change this public mini-app list.

In **Chappy Player → Chappy Apps 公開ライブラリ → Debug**, tap refresh
and select the mini-apps you actually want to install. The following eight
Debug entries are published and have verified package hashes:

| Debug mini-app | Permission(s) | Test purpose |
| --- | --- | --- |
| メモ帳 | none | Notes and saved app data |
| Chappy Media Lab | camera, microphone | Microphone and camera capture |
| Chappy Recorder | camera, microphone | Private video recording |
| Chappy Device Lab | motion, haptics | Motion sensors and vibration |
| Chappy File Lab | files | User-approved documents |
| Chappy Game Server Lab | network, motion, haptics | Explicit HTTPS/WSS game server testing |
| Chappy Touch Lab | none | Multi-touch pointer trails |
| Chappy Color Lab | none | RGB gradients and drawing response |

Stable still includes ASMR Sound Lab and the separately versioned
Chappy Recorder. Installing a package from either channel always needs the
user's confirmation, and permissions are requested by the host only on
explicit use. App ID collisions between channels follow the standard
update/confirmation flow; back up notes before intentionally switching an
installed app between channels.

If you previously installed a Debug APK containing the one-time bundled
samples, its **already-installed apps remain in its own Debug data storage**.
A subsequent Debug APK update does not delete those apps, their recordings,
or their user data. No new automatic samples will be installed on future starts.

## How to test the camera prototype safely

1. Download the `chappy-player-debug-apk` ZIP artifact from a **successful** `Build Android APK` workflow on the relevant commit. Unzip and install `app-debug.apk`. Do not uninstall the currently signed production application.
2. Confirm there are now **two separate launcher icons**: `Chappy Player Debug` and the existing `Chappy Player`.
3. Open **Chappy Apps 公開ライブラリ → Debug → 更新**, choose **Chappy Media Lab** and install it. Other examples can be installed individually from the same public list.
4. In Debug, choose the native video recording camera, desired 720/1080 quality and private storage. Allow Camera and optionally Microphone; test recording, stopping, dark mode recovery and in-app playback. Then verify Gallery/Google Photos does not index private MP4s.
5. Uninstall **only** `Chappy Player Debug` when done; doing so deletes Debug-only private recordings. It does not touch the production app.

## Quality and signing boundary

`tools/test_prepare_debug_variant.py` verifies Android Kotlin and Groovy build scripts are patched idempotently. The CI must compile an APK on this exact PR commit and validate that production signing workflow and source package identity remain unchanged.

There is no promise of Android physical-device correctness from CI alone. No signed production release is created by this PR.

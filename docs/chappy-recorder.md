# Chappy Recorder — standalone mini-app

Feature ID: RECORDER-01 | Source: `sample_apps/video_recorder/index.html` | Package: `local.chappy.recorder`

## Product behavior

Chappy Recorder is a focused **.chappy mini-app** for the existing Chappy Player Android CameraX video engine, not a second Android APK. It appears in the public **Chappy Apps → Debug** library, separate from Chappy Media Lab. Version 0.1.0.

1. On opening, read-only native storage stats show **available capacity / total capacity** of the internal filesystem where private MP4s are saved. Refresh on request, after recording, and on returning to foreground.
2. One-tap camera choice is a **rear/front toggle**, default rear.
3. Resolution 720p / 1080p, destination **private / gallery**, and optional microphone audio are selected before recording; controls lock during a recording.
4. **暗転モードで録画** requests normal per-session user confirmation and OS camera/mic permissions; after success it begins native CameraX MP4 and enters black-screen mode.
5. Dark mode keeps the display ON. Small upper-right status indicator is red during capture/finalization and green when idle; volume up restarts after a fully finalized stop within the same foreground approved dark session, volume down stops, and double-tap near the dot restores the UI.
6. **Right horizontal swipe near the dot** sets brightness to 100%; **left horizontal swipe** sets 1%. Flutter forwards this user gesture to Android only during the already foreground-approved dark session. This is **per-window brightness**, and the previous window brightness is restored when the user leaves dark mode, backgrounds the app, or exits. There is no background capture or OS privacy-indicator suppression.
7. **プライベート動画を表示** expands a collapsed list with filename/size/time, playback in Chappy Player and a delete button. Deletion is explicitly confirmed by the native host. Gallery-saved videos are not included in this list.

## Storage isolation and limits

Private files are scoped under the **mini-app owner ID**, so existing videos made in Chappy Media Lab are **not shown** in Chappy Recorder. This is intentional to avoid exposing one mini-app's private data to another. Export/migration of old recordings is not yet implemented. Do not uninstall or delete Chappy Player data to upgrade a Debug build while important private videos are present.

Storage readings reflect the *internal filesystem used for private files*, not removable SD cards or cloud quotas. Gallery save uses Android MediaStore and may reside on another volume on some devices. Capacity should not be treated as a guarantee of available continuous recording duration. Native output is currently capped at 1 GiB per capture.

The video bridge requires a compatible new Chappy Player Debug APK for `video.storageInfo()` and brightness-swipe handling. An older player may still expose start/stop but will report capacity unavailable and will not support brightness gestures.

## Test gates

- `node tools/test_chappy_recorder.js`: test source parses, lens selection, capacity, capture, dark transition, stop, private-list playback/deletion and volume restart notification.
- `python3 tools/test_native_video_contract.py`: permission and native bridge boundary checks, storage stats and per-window brightness.
- `python3 tools/pack_html_chappy.py --source sample_apps/video_recorder --id local.chappy.recorder --name 'Chappy Recorder' --version 0.1.0 --permission camera --permission microphone --output chappy-recorder.chappy`
- Flutter analyze/test and Android debug APK build in GitHub Actions. Manual Android 14 device QA remains necessary, including 720p/1080p lens availability, gallery storage, private playback/delete, volume key behavior, dark-mode double-tap and brightness swipe. No untested claim of device success.

## Future improvements

- RECORDER-02: export or share private MP4s after explicit user selection
- RECORDER-03: optional device-independent storage estimates / retention warnings
- RECORDER-04: robust long-recording and available-space warnings

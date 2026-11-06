# Chappy Player v0.3.0 — Camera recording production release

Target: **Signed production Android player** `dev.chappy.chappy_player`, installed in-place over v0.2.4 with the existing permanent production signing certificate. Separate from Debug player `dev.chappy.chappy_player.debug`.

## Release notes to enter in the GitHub Actions form

Chappy Player v0.3.0：CameraXを利用したユーザー操作による動画録画、720p/1080pと前後カメラ切り替え、非公開／ギャラリー保存、非公開動画一覧・再生・削除、暗転録画（赤／緑の状態ランプ、音量ボタンによる開始・停止、ダブルタップ復帰、右／左スワイプによる画面輝度変更）に対応。内部ストレージの空き容量表示も追加。プライバシー保護のため撮影はアプリが前面にあるときだけ動作し、Android標準のカメラ・マイク使用表示と許可画面を維持します。

## Production release gate

- Source merged into main, `Build Android APK` exact SHA green.
- Production publisher `.github/workflows/publish-signed-apks.yml` compiles three CPU-specific APKs and verifies **actual package ID**, monotonically increasing ABI-specific Android version codes, exact permanent pinned release signer and archive integrity.
- The source workflow now additionally runs `tools/test_native_video_contract.py`, `tools/test_android_media_manifest.py`, `tools/test_chappy_recorder.js`, `tools/test_media_lab_video.js` and JS bridge regression before it builds any release APK.
- Existing `CHAPPY_KEYSTORE_B64` and related signing secrets are used only in the manual signed release workflow; they must **not** be replaced with Debug keys or committed to the repository.
- The distribution process only publishes the three signed APKs + metadata to public `mibesamiti-png/chappy-player-updates`, then updates the production `update.json` from their actual SHA-256s.
- **No automatic public release on source push.** User must explicitly run GitHub Actions `Publish Signed APK Updates` on main with version `0.3.0` and the above release notes. The assistant cannot assume that a green debug CI run signs or publishes production APKs.
- Check successful production feed `https://raw.githubusercontent.com/mibesamiti-png/chappy-player-updates/main/update.json`: `version: 0.3.0`, `packageId: dev.chappy.chappy_player`, matching public release tag `v0.3.0-b<N>`.
- The public Stable Chappy Recorder publisher is gated on **this exact official signed production feed** reporting >=0.3.0, so production users are not offered a mini-app whose CameraX API is absent.

## Device QA remaining after CI

- Install the signed v0.3.0 over v0.2.4 via `プレイヤー本体の更新`, verify app files survive and Android signature preflight succeeds.
- Chappy Recorder Stable: capacity gauge, camera back/front, optional audio, 720p/1080p, private/gallery save, private list and explicit deletion, video playback, in-app display brightness swipes, double-tap recovery, status indicator and hardware volume controls.
- Android camera/microphone privacy indicators remain visible when required. The dark mode is *not* hardware screen-off recording or background capture; onPause stops recording.
- System bars can be temporarily re-shown by an edge swipe. Actual Android device behavior is platform dependent.
- **Never uninstall the existing player as a release migration**: internal private MP4s are erased on uninstall, and private MP4 export is not yet supported.

## Future data protection

- Add explicit private MP4 export/share before major migration or uninstall workflows.
- Production validation CI does not replace Android physical-device recording tests.

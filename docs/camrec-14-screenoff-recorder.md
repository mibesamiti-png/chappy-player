# CAMREC-14 R2 — 画面OFF録画 / OSのプライバシー表示は維持

## 目的と境界

2026-11-10要望：Chappy Recorderの緑色インジケーターが気になるので、スマホ画面を**物理的にOFF**にした状態でも録画を続けたい。**Androidが表示する緑点や権限履歴をプログラムで消す機能ではない**。画面OFF時は点が視覚的に見えないだけ。画面が再点灯すればシステムのカメラ・マイク使用表示は維持される。

今回のR2は **ユーザーが画面を見て明示的に許可した録画**だけを、CameraX + Android `camera`（音声付きなら`microphone`も） Foreground Serviceの管理へ移す。Android 11/API 30未満は安全側に未対応。Android 13以降は通知権限も明示要求し、通知拒否時は画面OFF録画を開始しない。通知経由の**停止ボタン**はシステム側で動く。

## 実装構造

- `tools/android/ChappyCameraService.kt`: 非exportのAndroid Foreground Service。Androidのカメラ/マイク権限を再検証、`startForeground()` を実行してからCameraXを起動する。録画の`LifecycleOwner`はActivityではなくサービス専用 `NativeVideoRecorder`。停止通知は非exportのBroadcastReceiverから既存サービスの停止だけを呼ぶ。Androidによる自動再開なし（`START_NOT_STICKY`）。
- `tools/android/NativeVideoRecorder.kt`: 従来のActivityと新サービスの双方で利用できる`Context`を受け取る。動画の保存先、CameraXの動き検知、1GiB上限は現状維持。 `VideoRecordEvent.Finalize`でMP4の保存結果が確定してから、サービスに完了通知を出す。
- `tools/android/MainActivity.kt`: 新オプション`screenOff=true`だけを前面Activityから開始。二重録画を拒否し、常に`camera`、音声があれば`microphone`、画面OFFなら`notifications`のAndroid権限を確認。普通の録画モードは従来のActivity終了時停止のまま。
- `lib/screens/app_runner_page.dart`: フォアグラウンドで本人同意した画面OFF録画セッションのみ、Flutterの背景化時に`stopNativeVideo`を実行しない。ただしWebViewのWebRTCトラック・通常ネイティブマイクは既存と同様に停止する。
- `sample_apps/video_recorder/index.html`: `画面OFFでも録画を続ける`を独立ボタンとして表示。対応本体/OSでのみ有効。画面OFFにする操作はOSの電源ボタンで本人が行い、プライバシー表示を隠すコードを実装しない。既存の暗転・動き検知・非公開保存・手動停止は維持。
- `tools/patch_android.py`: Flutterが生成するManifestへ`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_CAMERA`、`FOREGROUND_SERVICE_MICROPHONE`、`POST_NOTIFICATIONS`と非exportのservice/receiverを1度だけ追加。camera/micは他のミニアプリへ自動的に広く許可しない。

## 品質の境界

**Quick CIとAndroid 3ABIビルド成功は、スマホ実機で画面OFF中の映像が途切れないことを保証しない**。新機能はまずDebug専用。実機で以下を確認するまでは署名Stableへ移さない。

- 通常録画は画面ロック時に停止、画面OFF録画はサービスと通知を維持できること。画面OFF開始までのカメラ/マイク/通知権限を確認し、拒否時は失敗が表示されること。
- 画面がONの間はAndroidの緑色プライバシー表示が消えていないこと。ロック時は見えず、点灯後にシステムの使用表示・通知を確認。
- 録画中通知の停止を押すとMP4が確定し、再生/削除/書き出しが既存の非公開動画ライブラリからできること。
- 30秒、10分以上、画面OFF→復帰、ホーム→他アプリ→復帰、音声ON/OFF、前面/背面720p/1080p、静止一時停止/再開と録画終了、権限取消、通話、バッテリー最適化、空き容量不足を確認。
- スマホの省電力設定、機種別カメラ制限により録画が停止する場合は`Finalize`のエラー・保存ファイルを確認。Androidが強制終了したときに最後のMP4が失われる可能性をなくせるとは主張しない。
- 録画中に本体/ミニアプリを更新・アンインストールしない。プライベート保存はアプリデータ削除で消えるため事前バックアップ。

## 続き

実機QAが通ったら、フォアグラウンド録画・画面OFF録画の品質改善、通知状態同期、録画分割（1GiB上限）、R3の数秒のプリ録画、R4の任意AI動き認識へ進む。R1のスマート録画の感度/静止判定は現状維持。GitHub/Notion引き継ぎへCI番号・実機QAを必ず分けて記録。

公式：https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start
https://developer.android.com/about/versions/14/changes/fgs-types-required
https://developer.android.com/develop/background-work/services/fgs/launch
https://developer.android.com/media/camera/camerax/video-capture

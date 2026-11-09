# CAMREC-13 — Chappy Recorder スマート録画 R1 (2026-11-10)

## 要望・確定した順序

長時間録画の容量を抑えるため、ユーザーが明示的に録画を開始した場合だけ、映像差分で静止を検出し、保存を一時停止または完全終了する。基本の実装順序は **(1) 映像差分検知 → (2) 一時停止・再開／静止終了 → (3) Android foreground serviceによる画面OFF録画 → (4) 数秒分プリ録画、必要ならAI物体検出**。勝手に録画を開始しない。AndroidのOSカメラ/マイク使用インジケーターを隠さない。

## R1 実装（静的・CI検証後、Android端末での確認が別途必要）

- Source: `tools/android/NativeMotionAnalyzer.kt`、`tools/android/NativeVideoRecorder.kt`、`tools/android/MainActivity.kt`、`tools/patch_android.py`、`lib/screens/app_runner_page.dart`、`sample_apps/video_recorder/index.html`。
- モード3種類：**通常録画**（既定値で旧機能互換）／**静止中は一時停止**（動きを再検出するとresume）／**静止が続いたら完全終了**（MP4を確定）。静止判定10・30・60・120・300秒、感度0〜100（既定40）。
- ユーザーが録画前に選んだ設定だけを明示許可で送る。既存のカメラ・マイク権限は従来どおり毎回検証し、Android Activity が休止したら**必ず録画を停止**。今段階では画面OFF/他アプリ利用中の録画は不可。
- CameraX `VideoCapture` と `ImageAnalysis` の同時バインド。Y平面の16×12点を最大4Hzで取り込み、画面全体の輝度変化の平均を差し引いた後に局所画素の差分を測定。**原画像・顔・動画フレームをログ/メモリキャッシュ/JS/ネットワークへ渡さない。** `ImageProxy.close()` を必ず呼び、`KEEP_ONLY_LATEST` で負荷を抑える。
- 2回連続検出で動きが戻ったと判断。最初にCameraX `Start` が通知されてから静止時間を計測する。解析失敗時は**データ欠落を静止と判定せず、通常の録画継続に倒す**。Unsupported `VideoCapture+ImageAnalysis` でのバインドは明示的なエラー（自動で通常モードに落とさない）。
- `Recording.pause()` と `resume()` を使用。保存が一時停止している間も**カメラが稼働する**ため電池消費・OSのカメラ表示は継続。静止中の音声も保存から除かれる。**動きの直前数秒は現時点では残らない**（プリ録画は将来段階）。
- JS側はホストの `video.status()` が `motionMode` を報告したときだけスマート録画を選択可能にする。旧プレイヤーでは通常録画のみを許す。通知/実機検証なしに新規機能を成功とは言わない。
- 以前からの1 GiB/ファイル上限、private/mediaStore保存、ZIPバックアップ/復元、音量キー、暗転画面、OS privacy indicatorsは変更しない。

## R1テストと公開の境界

1. `node tools/test_chappy_recorder.js`：既存の保存/再生/復元/削除を含むシミュレーション、動き検知の設定引渡し、画面内の静止表示。
2. `python3 tools/test_motion_recorder_contract.py`：CameraX analyzer、ユーザー同意、静止モード、プライバシー、旧機能の安全性の静的契約。
3. Quick CIで`v0.1.4`の`.chappy` を**非公開プレビュー成果物**として出力。新機能にはAndroidネイティブ改修APKが必要なため、実機動作未検証のまま**公開Chappy Apps Debug/Stableには上書きしない**。新APK対応を確認してから、レビュー済みv0.1.4だけ公開Debugへ載せる。
4. Android Debug互換APKビルドでKotlinコンパイルが通るか実測。Quick CIだけでは実機録画成功を証明できない。

## 実機手動検証

- 通常録画：暗転、音量＋/-、保存、再生、privateライブラリ、画質・音声ON/OFFの回帰。
- 静止60秒で一時停止 → 静止状態が続いてもファイルが増えない → 動作2回連続サンプルでresume → MP4再生時に静止部分が飛んでいること。
- 「静止終了」10秒で停止してファイルが確定し、保存済み一覧に表示されること。
- カメラを動かさず照明のみON/OFFで反応しすぎないこと、小さな対象/画角全体が動くケースを比較し感度を調節。
- 1080p・前/背面の組み合わせでCameraX bind可能か。非対応なら安全にエラーを出し、勝手に通常録画しないこと。
- 途中でロック/ホーム/権限解除/電話着信/省電力/保存領域不足時に録画停止、保存結果やエラーが分かること。Androidのカメラ緑点・録画中通知はOSの仕様に従うこと。

## 将来R2 — 画面OFF・バックグラウンド録画（未実装）

- Manifest `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CAMERA`, マイク使用時は `FOREGROUND_SERVICE_MICROPHONE`、適切なservice type。画面が見える段階でユーザーが明示開始、サービス移管。
- CameraX `LifecycleOwner` をActivityではなくサービス側が所有。録画状態とファイル確定をサービス側の責務に変更。
- 録画中の常駐通知に経過時間と明示的な**停止**操作を表示。Android 14以降の使用中権限制限、端末固有省電力、画面消灯復帰、通知拒否とOS強制終了への対応。サイレント/不明な起動・権限表示回避は禁止。
- R3はプリ録画（数秒のリングバッファ、保存量/メモリ上限明記）、R4は必要に応じて物体認識AI。誤検知、プライバシー、電池・熱への影響で採否判断。

公式: https://developer.android.com/media/camera/camerax/analyze
https://developer.android.com/media/camera/camerax/video-capture
https://developer.android.com/media/camera/camerax/architecture
https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start

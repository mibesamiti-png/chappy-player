# カメラ・マイク対応 Phase 1 / Chappy Media Lab

## 目的と対応範囲

- Android WebViewでWeb標準の `navigator.mediaDevices.getUserMedia()` を使用し、カメラとマイクにアクセスする
- v1 `.chappy` の `manifest.json` で `permissions: ["camera"]`, `["microphone"]`, `["camera", "microphone"]` を明示する
- 端末ごとの権限確認をユーザー自身が行う。宣言のないミニアプリやWebViewの未対応リソース要求は拒否する
- ミニアプリごとに要求のたびに確認ダイアログを表示し、承認後にAndroidの実行時権限を確認する
- ホストは映像・音声のバイト列をログに残さず、ローカルWebViewへ渡す。ネット接続は従来のCSPで禁止
- トラックの終了/ページ終了/バックグラウンド移動時はJavaScriptで停止する。Android側でもWebView破棄時に取得を終了する
- 既存ミニアプリ（`permissions: []`）はそのまま動作し、権限を自動で付与しない
- 実機ではカメラ表示と解像度変更が成功。WebViewのマイク取得は未成功（NotReadableError）。新しいAndroid AudioRecord方式は実機未検証

## 利用する標準API

```js
const camera = await navigator.mediaDevices.getUserMedia({video: true});
const microphone = await navigator.mediaDevices.getUserMedia({audio: true});
// 終了時:
camera.getTracks().forEach(t => t.stop());
microphone.getTracks().forEach(t => t.stop());
```

Androidのカメラ/マイク権限はFlutterから `dev.chappy.player/media_permissions`
経由で要求し、`WebViewPermissionRequest.grant()` は権限宣言・プレイヤー確認・Androidの許可に合格した場合のみ呼ぶ。
位置情報、画面共有、Bluetooth、通話等は未実装であり今後も別の権限審査が必要。

## 実機テスト用 Chappy Media Lab

- ソース: `sample_apps/media_probe/index.html`
- パッケージID: `local.chappy.media_probe`
- 追加権限: `camera`, `microphone`
- ビルド: `Build Android APK` Actions の `chappy-media-probe` 成果物の `media-probe.chappy` を取得
- ミニアプリは公開ライブラリの **Debug** に掲載（Stable未公開）。v0.1.1では基本/高度なマイク比較、v0.1.2ではカメラ解像度・マイク機器診断を追加。ネイティブマイク試験用v0.1.3は新しいAPKが配布されるまで公開ライブラリへ反映しない

ローカルでの作成:

```sh
python3 tools/pack_html_chappy.py --source sample_apps/media_probe \
  --id local.chappy.media_probe --name "Chappy Media Lab" \
  --version 0.1.3 --permission camera --permission microphone \
  --output media-probe.chappy
```

## Android実機QA

1. カメラ/マイク権限を持たない既存メモ帳・ASMRアプリが引き続き動く
2. 新しい本体の正式署名APKを **上書き** し、既存ASMR設定と保存データが残る
3. `media-probe.chappy` を読み込み、権限表示が「カメラ・マイク」になっていることを確認する
4. カメラ開始でプレイヤー独自ダイアログ→OS権限→カメラプレビューが表示される
5. 撮影ボタンで静止画がアプリ内プレビューに表示される（外部ファイルへの保存は未対応）
6. マイク開始でプレイヤー独自ダイアログ→OS権限→波形・RMSが動く。まず「基本入力」を試す。成功したら「高度な入力設定」でも比較する
7. `NotReadableError: Could not start audio source` が出た場合、マイク競合・端末設定とWebView依存の問題を切り分ける。診断ログで失敗フェーズ（getUserMedia/AudioContext）を確認する
8. 拒否した場合、アプリが失敗理由を表示し、診断ログに拒否が残る
9. 停止・画面退出・バックグラウンド移動でカメラ/マイクのOSプライバシーインジケーターが消える
10. システム設定で権限を取り消してから再起動すると再び許可が必要になる
11. カメラのない端末や別のWebViewバージョンでもクラッシュせず理由を表示する

## 調査中: マイクの NotReadableError と Android 権限

- 実機ではWebViewのカメラ表示が成功。一方マイクはAndroidの権限ダイアログで承認されても `NotReadableError: Could not start audio source` が発生
- `media-permission: Granted` は**WebViewへリソース取得を許可した事実**のみを示し、音声デバイスが起動できたことを保証しない
- AndroidManifestに `android.permission.MODIFY_AUDIO_SETTINGS` を明示する修正案を別PRで作成。これはAndroidのnormal権限であり、ミニアプリへのAPI公開ではない
- この修正が根本原因かは **未確認**。本体の次の正式署名APKで実機比較が必要。保存データは削除しない
- 失敗時はマイクのプライバシー設定、他の録音アプリ、Bluetooth/USBマイクの接続状態、Android System WebViewバージョンを記録し、音声データそのものは収集しない
- バックグラウンド録音はこの改修に含まない

## Androidネイティブ AudioRecord 方式（実装候補・未リリース）

- `WebView.getUserMedia()` が許可後に `NotReadableError` になる一部端末向けに、`tools/android/NativeMicCapture.kt` を追加する新方式。WebView経由の録音とは別にAndroidが直接マイク入力を取得する
- ChappyのJS APIは `Chappy.microphone.start()`, `Chappy.microphone.levels()`, `Chappy.microphone.stop()`
- Android側はMono 16kHzを優先し、MICの48kHzまたはVOICE_RECOGNITION入力源へ限定的にフォールバックする
- ミニアプリ側は、マイク権限がマニフェストで宣言されていること、プレイヤーの毎回許可ダイアログ、AndroidのRECORD_AUDIO許可、画面表示中の4条件が必須
- `levels()` は **64個の粗い振幅エンベロープ、RMS、読取フレーム数** のみ返す。生PCM、音声ファイル、音声ログは保存・送信しない。ChappyのループバックCSPは従来通り
- バックグラウンド移行、ミニアプリ画面からの退出、Activity停止で必ず `AudioRecord.stop()` を呼び、録音を終了する
- `sample_apps/media_probe/index.html` v0.1.3にネイティブマイクの開始・停止と波形表示ボタンを追加した（既存WebView方式も保持）。対応する新しい正式署名APKが必須
- このPRは **実機未検証・未署名・未リリース**。CIがランナー起動前で失敗する間はmainへマージしない

### ネイティブ方式の実機テスト

1. 正式署名APKを上書きインストールし、既存ASMRデータの保持を確認する
2. `Chappy Media Lab v0.1.3` を開く。WebViewマイクは以前のエラーを再現してよい
3. 「Androidネイティブマイクを開始」→プレイヤーの許可→Android権限の順で明示的に承認する
4. `Android AudioRecord取得成功` が表示され、話しかけると波形とRMSが変化する
5. 権限拒否時はマイクが起動しない。カメラは従来通り動く
6. 画面を離れる/ホームへ戻る/画面消灯で録音停止し、Androidのマイク使用インジケーターが消える
7. 連続開始・停止と、通話・別アプリ利用後の復帰でクラッシュしない
8. ネイティブも失敗する場合は、Androidの録音ルーティング・端末プライバシー設定を重点調査する。成功した場合はWebView固有のWebRTC入力経路が疑わしい

## 制限

- 初期段階の対象は信頼できる自作ミニアプリ。任意の第三者製パッケージ用の完全な安全サンドボックスではない
- Androidがアプリ自体に許可した権限はシステム設定からいつでも取り消せる。プレイヤー側はWebViewからの要求ごとに確認する
- 外部Webサイトへの通信は不可。カメラ・マイク取得から録画ファイル保存・ライブ配信・バックグラウンド録音に拡張するには追加の設計と確認が必要
- ステレオ入力は端末・Android OS・WebViewの実際の実装に依存し、`channelCount: 2` は希望値であり保証ではない

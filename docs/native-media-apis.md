# カメラ・マイク対応 Phase 1 / Chappy Media Lab

## 目的と対応範囲

- Android WebViewでWeb標準の `navigator.mediaDevices.getUserMedia()` を使用し、カメラとマイクにアクセスする
- v1 `.chappy` の `manifest.json` で `permissions: ["camera"]`, `["microphone"]`, `["camera", "microphone"]` を明示する
- 端末ごとの権限確認をユーザー自身が行う。宣言のないミニアプリやWebViewの未対応リソース要求は拒否する
- ミニアプリごとに要求のたびに確認ダイアログを表示し、承認後にAndroidの実行時権限を確認する
- ホストは映像・音声のバイト列をログに残さず、ローカルWebViewへ渡す。ネット接続は従来のCSPで禁止
- トラックの終了/ページ終了/バックグラウンド移動時はJavaScriptで停止する。Android側でもWebView破棄時に取得を終了する
- 既存ミニアプリ（`permissions: []`）はそのまま動作し、権限を自動で付与しない
- 現時点で実機検証はまだ。Android WebViewによるハードウェア依存の挙動は未知

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
- ミニアプリは公開ライブラリの **Debug** に掲載（Stable未公開）。実機のマイク取得エラーを調べるため、v0.1.1から「基本入力（audio: true）」と「高度な入力設定」の切替を追加

ローカルでの作成:

```sh
python3 tools/pack_html_chappy.py --source sample_apps/media_probe \
  --id local.chappy.media_probe --name "Chappy Media Lab" \
  --version 0.1.1 --permission camera --permission microphone \
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

## 制限

- 初期段階の対象は信頼できる自作ミニアプリ。任意の第三者製パッケージ用の完全な安全サンドボックスではない
- Androidがアプリ自体に許可した権限はシステム設定からいつでも取り消せる。プレイヤー側はWebViewからの要求ごとに確認する
- 外部Webサイトへの通信は不可。カメラ・マイク取得から録画ファイル保存・ライブ配信・バックグラウンド録音に拡張するには追加の設計と確認が必要
- ステレオ入力は端末・Android OS・WebViewの実際の実装に依存し、`channelCount: 2` は希望値であり保証ではない

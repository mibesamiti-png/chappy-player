# Chappy Player: バックグラウンド音楽再生（設計 / 未実装）

作成: 2026-11-05。対象: Androidの音声ファイル再生。**この文書は仕様案であり、バックグラウンド再生のコードはまだ提供していない。**

## なぜ必要か

現在のミニアプリはAndroid WebView上で動く。WebViewのJavaScript/Web Audioを
画面消灯中や他アプリ使用中に常時動かす保証はない。ユーザーの明示操作で音声を再生する場合だけ、
再生責務をAndroid側のバックグラウンド再生サービスへ移管する。

推奨: AndroidX Media3の `MediaSessionService` + `ExoPlayer`。
Android公式: https://developer.android.com/media/media3/session/background-playback

**第1段階は、.chappy内部に同梱した音声ファイルの再生のみ**。
マイク・カメラ・位置情報・任意URL・任意JavaScriptのバックグラウンド実行は対象外。
現在のASMR Sound LabはWeb Audioで合成する音が中心なので、そのまま
ネイティブファイルプレイヤーへ移行できるとは限らない。
リアルタイム音響エンジンは別途検討する。

## 機能ID / 状態管理

| ID | 機能 | 状態 | 必須検証 |
|---|---|---|---|
| BG-AUDIO-01 | 音声ファイル再生MediaSessionService | 未実装 | Android実機画面消灯 |
| BG-AUDIO-02 | .chappy `backgroundAudio` 権限宣言 | 未実装 | 権限なしアプリ拒否 |
| BG-AUDIO-03 | Android用安全な相対アセット解決 | 未実装 | パストラバーサル・シンボリックリンク拒否 |
| BG-AUDIO-04 | JSブリッジと許可ダイアログ | 未実装 | ユーザー起点／拒否／別アプリの乗っ取り防止 |
| BG-AUDIO-05 | 再生・停止・一時停止・シーク・ループ | 未実装 | 通知コントロールからの停止 |
| BG-AUDIO-06 | Audio focus / 通話 / イヤホン抜去処理 | 未実装 | 割り込みと復帰 |
| BG-AUDIO-07 | アプリ更新・削除時の安全な停止 | 未実装 | 保存データ非破壊 |
| BG-AUDIO-08 | 標準診断ログと端末実機QA | 未実装 | Android 13〜15等 |
| BG-AUDIO-09 | Web Audioリアルタイム合成音の継続 | 未実装・別研究 | 遅延・バッテリー・安全性 |

## フェーズ1 API案（まだ追加しない）

現在の `manifest.json` の許可名は `camera` と `microphone` のみ。
ネイティブ実装・検証が終わるまでは `backgroundAudio` を有効な許可名にしない。

想定マニフェスト:

```json
{
  "permissions": ["backgroundAudio"]
}
```

想定利用法:

```js
await Chappy.backgroundAudio.play({
  asset: "audio/relaxation.mp3",
  title: "Relaxation",
  loop: true
});
await Chappy.backgroundAudio.pause();
await Chappy.backgroundAudio.resume();
await Chappy.backgroundAudio.seek({positionMs: 10000});
await Chappy.backgroundAudio.stop();
const state = await Chappy.backgroundAudio.getState();
```

必須契約:

1. `asset` はインストール済みパッケージ内の相対パスに限定（ネットワークURL、`content://`、絶対パス、`../` を拒否）。
2. DartとKotlinの両方でcanonical pathが該当ミニアプリの `current/` 以下であることを確認。リンク・不審な拡張子・ディレクトリを拒否。
3. 1つのミニアプリが操作を開始するときは、前面での明示的なユーザー操作／利用許可が必要。別アプリによる再生乗っ取りを防止。
4. 音声を再生するミニアプリの識別子を通知に表示し、Android通知/ロック画面から停止可能にする。
5. `Chappy.backgroundAudio` は音声データ本体をJSブリッジへBase64で運ばず、ファイルの参照だけを渡す。
6. 他アプリの音声への割り込み、着信、ヘッドフォン抜去、Bluetooth切断で必要に応じて停止/一時停止する。
7. 明示的にバックグラウンド再生を許可された音楽のみをサービスで維持。ミニアプリのWebViewとJavaScript処理は引き続きバックグラウンド動作を保証しない。
8. ミニアプリ更新／削除／ロールバックで再生中アセットの整合性が失われる場合は、停止・リリースしてから安全に入れ替える。
9. ライブラリの保存データやAPK署名・更新ロールバック処理を変更しない。

## Android実装

- `androidx.media3:media3-exoplayer` と `androidx.media3:media3-session` を
  Androidビルド設定へ、互換性を確認した同一バージョンで追加する。
- AndroidManifestに以下を追加:
  - `android.permission.FOREGROUND_SERVICE`
  - `android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK`
  - `android:foregroundServiceType="mediaPlayback"` を持つMediaSessionService
- サービスはAndroid側でプレイヤーとMediaSessionを所有し、Activity/WebViewから分離。
- 再生終了時はサービスを停止し通知を消す。任意のバックグラウンド常駐はしない。
- 現在の `webview_flutter` とループバックCSPに追加ネットワーク権限を与えない。
- フェーズ1では安全な同梱音源のみ。外部音楽ファイルの選択は別権限設計。
- サービスを起動する前にforeground/ユーザー起点を検証する。バックグラウンドから無条件に新規起動しない。

## 段階別実装計画

1. 仕様＋純粋Dartパス/権限判定と回帰テスト、Manifest patchテスト
2. Kotlin MediaSessionServiceを非公開の本体機能として導入し、通知・停止を単体検証
3. 安全なFlutter MethodChannelとミニアプリ専用の認可UIを追加
4. `backgroundAudio` マニフェスト権限を有効化し、JS APIへ接続
5. 最小のオフラインBGMテストミニアプリをDebugへ配布
6. 正式署名APKで上書き・長時間・画面消灯・割り込み・権限拒否を実機検証

## 分離するタスク

- **マイクのNotReadableError:** `docs/native-media-apis.md` と専用修正PRで追跡。バックグラウンド音楽再生とは別の不具合。
- **バックグラウンド録音／撮影:** 別のAndroid権限・通知・Foreground Service typeと利用者承認が必要。安易に音楽再生と共有しない。
- **OTA / APK Stable・Debug:** アプリ更新の設計と独立して進める。

## デバッグ/受け入れ条件

- 音声再生開始→ホームへ移動→画面消灯でも再生が続き、通知から停止できる。
- 他のミニアプリが勝手に既存の再生を乗っ取れない。権限なしミニアプリは拒否。
- 停止・一時停止・再生再開・シークが正確で、連打でもクラッシュしない。
- 通話、音声フォーカス競合、Bluetooth・イヤホン切断に対応。
- バッテリー/プロセスキル後のAndroid動作は保証しすぎない。OS制限を明示する。
- ミニアプリ削除・本体APK更新・ロールバック後も保存データは残る。
- `flutter analyze` / `flutter test` / Gradleビルド / 権限セキュリティテストとAndroid実機テストを別々に記録する。

# Chappy Player 本体更新センター（段階的実装）

2026-11-04: コード作成。Android実機での更新ダウンロード・署名更新は未検証。

## 目的

従来の「GitHub Actions → artifact ZIP → APK解凍」から、
「プレイヤー内で更新確認 → 正しいCPU向けAPKを取得 → 検証 → 保存」へ移行する。

安全な更新を実現するため、**APKのインストールはまだ自動化しない**。
デバッグAPKはGitHub Actions実行ごとに署名が異なる場合があり、
Android側で上書きが拒否され得る。固定署名版へ切り替える前に
`.chappybackup`を端末外に保存しておくこと。

## 実装済み（コード作成）

- ホーム右上に「プレイヤー本体の更新」画面を追加
- インストール済みアプリのバージョン名とビルド番号を表示
- Dart VMの実ABIで `arm64-v8a` 等を選択
- 配信先のHTTPS JSONを最大64KiBで取得（リダイレクト拒否）
- `packageId` / `version` / `buildNumber` / `artifacts` を検証
- 更新がある場合のみ対応CPUのAPKをダウンロード
- APKをサイズ上限180MiBで制限し、受信した全バイトのSHA-256を照合
- 検証済みAPKのみAndroidのファイル保存ダイアログに渡す
- HTTPS以外の配信先、改ざんやファイルサイズ不一致を拒否
- ZIPやGitHubトークンをAPKに埋め込まない
- 配信先未設定のビルドは「利用不可」を明示しネットワークアクセスしない

## まだ未実装

- 起動時の定期チェック、通知、更新ON/OFF設定
- Androidインストーラーの直接起動・インストール完了検知
- 固定署名の秘密鍵とリリースビルドの設定
- 一般公開可能な配布先とAPKの発行
- 本物のAndroidでのファイル保存・上書きインストール検証

## 公開配信フィード

ソースのGitHubリポジトリ `mibesamiti-png/chappy-player` は非公開のままでよい。
ただし非公開Actionsのartifactは匿名HTTPSでは取得できない。
**公開可能なアップデート専用配布元**が別に必要となる。
鍵・トークンをクライアント側へ埋め込まないこと。

アプリのビルド時に次を指定する：

```bash
flutter build apk --release \
  --build-number 42 \
  --dart-define=CHAPPY_UPDATE_FEED_URL=https://updates.example.org/chappy-update.json
```

GitHub Actionsの手動署名リリースビルドは、Repository variable
`CHAPPY_UPDATE_FEED_URL`が設定されている場合にそれを埋め込む。
未設定時は更新チェック画面が説明文を表示するだけとなる。

更新フィード例（ダミーのURLとSHA。実際のファイルではない）：

```json
{
  "schemaVersion": 1,
  "packageId": "dev.chappy.chappy_player",
  "version": "0.2.0",
  "buildNumber": 42,
  "releaseNotes": "日本語メモ帳の起動不具合を修正",
  "artifacts": [
    {
      "abi": "arm64-v8a",
      "url": "https://updates.example.org/ChappyPlayer-arm64.apk",
      "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "sizeBytes": 80000000
    }
  ]
}
```

`tools/generate_update_feed.py` は実際のAPKのSHA-256とサイズから
正しいフィードJSONを生成する（APKそのものはアップロードしない）。

**セキュリティ**：SHA-256はフィードとファイル間の整合性検証。
配信フィード自体が攻撃者に変更された場合に備える独立の署名検証はまだない。
最終的にAndroidのAPK署名一致チェックも必須。今はインストーラーに渡さず、
ユーザーが選択した場所へ検証済みファイルを保存する段階。

## Android実機で次に試すこと

QA-03：2026-11-04、Xiaomi 11T Pro / Android 14でメモ帳起動・日本語入力成功。
次はQA-04：メモを保存してプレイヤー再起動後も残るか確認。
続けてQA-13：セルフチェック結果4項目。
アップデートセンターは配布先がまだ無いため未実機検証。

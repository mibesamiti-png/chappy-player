# Chappy Player — Flutter MVP v0.1.0

**Android向け・自分専用の `.chappy` ミニアプリプレイヤー（試作コード）**

最初に Flutter 製 APK を1回入れて、以後は `.chappy` (ZIP) ファイルをスマホで読み込む。

## 収録されているもの

- `lib/` — Flutterホーム画面、追加/更新/旧版復元/削除、WebView実行
- `lib/core/` — ZIP事前検証、オフラインサーバー、アプリ別JSON保存、診断ログ
- `sample_memo.chappy` — 手入力と自動保存を試せる実例（`sample_apps/memo/` がソース）
- `sample_memo_update.chappy` — 同一IDのv0.1.1更新版。更新・データ保持・旧版復元を試せる
- `test/` — マニフェスト・パス検証のユニットテスト
- `.github/workflows/build-android.yml` — Flutter test/analyze とデバッグAPK作成
- `tools/patch_android.py` — Androidマニフェストのループバック設定

## 現在の検証状況（2026-11-04）

- `main` のビルド #5 は **Flutter解析・ユニットテスト・debug APK生成が成功**。ただしAndroid実機は未検証。
- PR #1 ではインポート前のアプリ情報プレビュー・異常終了後の復旧・回帰テストを追加。マージ前にPRのActionsが成功することを確認する。
- JavaScriptブリッジのNodeスモークテストをActionsにも追加。
- 現段階でカメラ・ネット通信・一般の非信頼パッケージ用サンドボックスは未対応。

## APKの作り方（GitHub Actions）

1. **新しいプライベートGitHubリポジトリ**を作り、このプロジェクトのファイルとフォルダを配置する（ZIP単体をGitHubへ置いただけでは展開されません）。
2. `Actions` → `Build Android APK` → `Run workflow` を選択（pushでも実行）。
3. ワークフローが成功したら `chappy-player-debug-apk` アーティファクトを取得する。
4. APKをAndroidで開いてインストールする。端末設定によっては不明なアプリのインストールを許可する必要がある。
5. Chappy Playerを開いて、同梱の `sample_memo.chappy` をインポートする。
6. メモ入力→保存→アプリを閉じる→再起動して内容の保持を検証する。
7. サンプル内の「テスト用エラー」を押して、プレイヤーのバグアイコンから診断ログを確認。
8. `sample_memo_update.chappy` を読み込み更新、メモが残ることを確認。メニューから「旧版に戻す」を試す。

**ビルド環境を自分で構築する場合**：Flutter 3.32以降を導入し、プロジェクト直下で以下を実行。

```bash
flutter create --platforms=android --org dev.chappy .
python3 tools/patch_android.py
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

> このZIPにはFlutterが生成するAndroidランナーフォルダは含めていない。`flutter create` で生成する方式。
> デバッグAPKは個人テスト用。正式配布では署名・更新キー管理を別途設計する。

## APK更新と署名について（重要）

現段階でActionsが生成する `app-debug.apk` は**使い捨ての個人テスト用**です。GitHub Actionsの別の実行で署名鍵が変わると、Androidは既存APKへの上書きインストールを拒否します。

プレイヤーAPKをアンインストールすると、アプリ内に保存されたメモ等のデータも削除されます。固定署名とバックアップ/復元機能が完成するまでは、重要な実データを保存しないでください。

将来的にはGitHub ActionsのSecretに固定署名鍵を安全に保管し、同一署名・単調増加するversionCodeで更新できるリリースAPKを作る予定です。この署名鍵はソースコードにコミットしません。なお、`.chappy` パッケージだけの更新にはAPK再署名は不要です。

## `.chappy` v1 仕様

ZIPのルートに `manifest.json`, `index.html` を置く。`main.js`, `style.css`, `assets/` などを配置可能。

```json
{
  "formatVersion": 1,
  "id": "local.chappy.memo",
  "name": "メモ帳",
  "version": "0.1.0",
  "minPlayerVersion": "0.1.0",
  "entry": "index.html",
  "permissions": []
}
```

現在対応するJS API：

```js
await Chappy.storage.set('notes', 'hello');
const value = await Chappy.storage.get('notes');
await Chappy.storage.remove('notes');
const info = await Chappy.info();
await Chappy.log('diagnostic message');
```

取り込み制限：ZIP 12MiB、展開合計24MiB、200ファイルまで、個々10MiBまで、ASCIIパスのみ。シンボリックリンク・暗号化ZIP・Zip64・パストラバーサル・過大圧縮率は拒否。保存データはアプリにつき1MiB。

## セキュリティ方針と制限（重要）

- **現在は信頼できる自作 `.chappy` のみ読み込むこと**。不特定多数のアプリを安全に実行するサンドボックスとしては未完成。
- アプリごとに**一時的な異なるloopbackポート**から静的ファイルを配信するためオリジンが分離される。通信は `connect-src 'none'` のCSPで禁止。アプリ自身の画像/JS/CSSだけ読み込む。
- HTTPサーバーは 127.0.0.1 にのみバインド。Androidマニフェストにはローカル配信用 `INTERNET` / `usesCleartextTraffic` が必要。ネットワーク権限を使った外部アクセスはv0.1では公開しない。
- ブリッジは storage/info/log のみに限定。カメラ、マイク、Bluetooth、バックグラウンド通信は**未実装**。
- WebViewのJavaScript実行には固有のリスクがある。現段階で無条件に外部由来の `.chappy` をインストールしてはいけない。
- 診断レポートは自動送信されない。ログにアプリが書いた文言が入るので、共有前に確認する。
- FPS計測、ZIP形式レポート、アプリごとのユーザー権限画面、復旧ジャーナル、ネット通信、性能測定、カメラ等は今後の予定。

## 実装状況

| 項目 | 状態 |
|---|---|
| Flutter UI / アプリ一覧 | コード作成済、実機未検証 |
| ZIP検証・インポート | コード作成済、Flutterテスト未実行 |
| WebViewオフライン起動 | コード作成済、実機未検証 |
| JS↔Flutter 保存API | コード作成済、実機未検証 |
| 更新・旧版復元 | コード作成済、異常終了リカバリー未実装 |
| ログ収集・コピー | コード作成済、実機未検証 |
| APKビルド | main #5 にてGitHub Actions成功、Android実機未検証 |

このチャットのローカル環境にはFlutter SDKがない。Flutter解析・ユニットテスト・APKビルドはGitHub Actionsで成功済み。Android実機検証は未実施。

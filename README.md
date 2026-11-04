# Chappy Player — Flutter MVP v0.1.0

**Android向け・自分専用の `.chappy` ミニアプリプレイヤー（試作コード）**

最初に Flutter 製 APK を1回入れて、以後は `.chappy` (ZIP) ファイルをスマホで読み込む。

## 本体アプリの簡単更新（開発中）

Xiaomi 11T Pro / Android 14 の実機で、メモ帳の表示・保存・
バックアップ復元を確認済み。更新センターにはCPU形式の自動判別、
HTTPSダウンロード、SHA-256・署名・バージョン事前検証、
Android標準インストーラーへのワンタップ引き渡しを追加済み。

**デバッグAPK同士は署名が異なる場合があるため、まだ継続的な上書き更新には使わないこと。**
固定署名と公開APK配布が利用できるようになると、通常はアンインストールせず更新できる。

公開APK専用の`mibesamiti-png/chappy-player-updates`リポジトリを
別途作る計画。**現時点ではまだ未作成で、公開APKも未配布。**
新しい手動専用ワークフロー `Publish Signed APK Updates` は、
署名鍵・配布専用トークンが無い間は実行に失敗する安全設計。

一回だけ必要な設定：[公開APK配布の初期設定](docs/public-apk-distribution-setup.md)

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

## デバッグ記録モードと診断レポート（開発中）

プレイヤーの**虫アイコン（診断ログ）**で以下を実行。

1. 「記録開始」を押す。ミニアプリから開けばそのアプリのログを対象にする。ホームから開くと全アプリが対象。
2. 戻る操作で問題のあるミニアプリに戻り、不具合を再現する。
3. もう一度診断ログを開き、「再現手順をメモ」で発生時の操作を記録できる。
4. 「記録終了」を押す。
5. 画面右上のコピーボタン、またはファイル保存ボタンからテキストレポートを取り出す。

記録内容：JavaScriptコンソール・エラー、Flutter側の例外、ブリッジAPIの失敗、開始・終了時刻、手入力した再現メモ。最大500件で古い記録は自動的に省略され、レポートにその旨が記載される。

**プライバシー**：自動で画面録画・キー入力取得・スクリーンショット撮影・外部送信はしない。ログそのものにユーザー入力やURL等が含まれる可能性があるため、外部共有前に必ず内容を確認する。

**復旧**：記録の開始・終了時刻と対象アプリIDは端末へ保存する。異常終了などで記録終了を押せなかった場合、次回起動時に保存済みの診断ログから記録を復元して「前回の異常終了から復旧」と表示する。直前のログがファイルへ書き込まれる前に端末が停止した場合やログ容量上限によるローテーション時には、一部の記録が失われる可能性がある。ログ画面は更新アイコンで一覧を再表示する。Android実機での操作は未検証。

## 初回起動のワンタップテスト

「サンプルメモ帳を追加してテスト」をタップすると、APKに同梱した
`sample_memo.chappy` を検証・インストールする。Androidファイルピッカーや
別ダウンロードは不要。同じIDのアプリがある場合、上書き確認後に本体を
更新し、保存データは保持する。

任意の `.chappy` をファイルからインポートする従来の機能も継続。
実機での操作は未検証。

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

## 保存データのバックアップと復元（開発中）

ホーム画面の「保存データをバックアップ」「保存データを復元」から利用する。

- バックアップは `.chappybackup`（UTF-8 JSON）形式。最大12MiB／100アプリ、1アプリ当たり1MiB。
- 保存するのはアプリ別のJSON保存データのみ。**`.chappy` 本体、旧版、デバッグログは含まない**。本体は別途保管すること。
- Androidのファイル保存画面で、端末の外部ストレージやクラウドなどにバックアップを保存する。
- 復元前にアプリID・件数・作成日時を確認してから実行。同じIDのデータは上書きする。
- 強制終了に備え、復元中は旧データを一時的に退避し、次回起動時に中断された復元を取り消す。
- **暗号化なし**。メモ本文などが含まれるため、バックアップファイルを他人へ公開しないこと。

バックアップ→APKアンインストール→新APKインストール→復元→`.chappy` の再インポート、の順でデータ移行が可能（実機動作は未検証）。

## 固定署名のAPKビルド（開発中）

`.github/workflows/release-android.yml` に手動実行の `Build Signed Release APK` を用意。
GitHubリポジトリの **Settings → Secrets and variables → Actions** に以下4件を登録するまで実行できない。

| Secret | 内容 |
|---|---|
| `CHAPPY_KEYSTORE_B64` | 同じAndroid署名キーストアファイルをBase64化した値 |
| `CHAPPY_STORE_PASSWORD` | キーストアのパスワード |
| `CHAPPY_KEY_PASSWORD` | 鍵のパスワード |
| `CHAPPY_KEY_ALIAS` | 署名鍵のエイリアス |

署名鍵の生成例（手元の安全な環境）：

```bash
keytool -genkeypair -v -keystore chappy-release.jks -alias chappy -keyalg RSA -keysize 3072 -validity 10000
# Base64 encoding example (macOS/Linux)
base64 -w 0 chappy-release.jks
```

環境によってBase64のコマンドオプションは異なる。鍵とパスワードはGitHubのソースコードやチャットに貼り付けないこと。
**署名鍵の紛失は同じアプリIDのAPKを上書き更新できなくなる原因になる**ため、秘密情報を安全な場所に控えておくこと。

同じ署名鍵を使い、かつversionCodeを増やしたAPKなら上書き更新可能。GitHub Actionsではrun_numberをbuild-numberに指定している。
なお、既存のデバッグAPKと新しいリリースAPKでは署名が異なるため、そのままの上書き更新は通常できない。最初の切替前に必ずバックアップを保存する。

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

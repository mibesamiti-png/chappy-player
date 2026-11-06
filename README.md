# Chappy Player — 個人用Androidミニアプリプレイヤー

**Android向け・自分専用の `.chappy` ミニアプリプレイヤー（試作コード）**

最初に Flutter 製 APK を1回入れて、以後は `.chappy` (ZIP) ファイルをスマホで読み込む。

## 正式署名APK・アプリ内更新（2026-11-04）

Xiaomi 11T Pro / Android 14 でサンプルメモの表示・保存・バックアップ復元を検証済み。
正式署名版 **v0.2.0 (Build 5)** はGitHub Actionsからのビルド・署名検証・公開が成功し、Android端末へのインストールも確認済み。

- 公開APK（**アプリ本体のみ**）：[chappy-player-updates Releases](https://github.com/mibesamiti-png/chappy-player-updates/releases)
- ソースコード：この公開リポジトリ。秘密の署名鍵・トークンはGitHub Actions Secretsで厳重に分離
- 配布フィード：`https://raw.githubusercontent.com/mibesamiti-png/chappy-player-updates/main/update.json`
- 署名鍵：GitHub Secretsの固定署名鍵を継続使用。署名の変更やビルド番号の巻き戻しは公開前に拒否
- ユーザー確認付きのアプリ内更新：HTTPS、SHA-256、パッケージID、署名、ビルド番号を検証しAndroid標準インストーラーに引き渡す

**次の目標：v0.2.1へ、アプリ内から上書き更新できるか実機テストする。** Android 14での本体更新成功はまだ未検証。
テスト手順：[初回上書き更新のチェックリスト](docs/android-update-smoke-test.md)。
初期設定：[公開APK配布の初期設定](docs/public-apk-distribution-setup.md)。

## 次期アップデートの開発内容（まだ正式APK未配布）

- `Publish Signed APK Updates` は **手動実行のみ**。開発中のPRマージでは正式APKを公開しない。
- AndroidのCPU別APKビルド番号の扱いを修正。`--split-per-abi` でARM32+1000 / ARM64+2000 / x86_64+4000の番号を確認し、各ABI別に比較する。
- プレイヤー更新センターにGitHub公開Releasesからのバージョン履歴一覧と、上書き可能な更新版を選択する機能を追加。
- `Chappy Apps`：Public `mibesamiti-png/chappy-apps` の Stable / Debugカタログと、SHA-256・ZIP検証・確認付きミニアプリ追加/更新。
- Android「ファイルで開く」「共有」からの `.chappy` 直接受信と、既存インポートの共通化。
- HTMLを `.chappy` へ梱包し、公開Stable / Debug用 `catalog.json` を生成するCLIを追加。

**公開用 `chappy-apps` リポジトリは作成済み**：[mibesamiti-png/chappy-apps](https://github.com/mibesamiti-png/chappy-apps)。Stable / Debugのミニアプリを配布する。APIキーや個人的な保存データは登録しない。
詳細：[公開カタログ](docs/chappy-apps-catalog.md) / [ファイル直接取り込み](docs/android-external-chappy.md) / [HTML移植](docs/html-to-chappy.md)。
実機でのファイル連携・本体更新の成功は未確認。次の署名付きAPKにまとめた後でテストする。

## 収録されているもの

- `lib/` — Flutterホーム画面、追加/更新/旧版復元/削除、WebView実行
- `lib/core/` — ZIP事前検証、オフラインサーバー、アプリ別JSON保存、診断ログ
- `sample_memo.chappy` — 手入力と自動保存を試せる実例（`sample_apps/memo/` がソース）
- `sample_memo_update.chappy` — 同一IDのv0.1.1更新版。更新・データ保持・旧版復元を試せる
- `test/` — マニフェスト・パス検証のユニットテスト
- `.github/workflows/build-android.yml` — Flutter test/analyze とデバッグAPK作成
- `tools/patch_android.py` — Androidマニフェストのループバック設定

## 現在の検証状況（2026-11-04）

- 正式版 **v0.2.0 (Build 5)** は、GitHub Actionsの署名付きAPKビルド・証明書指紋照合・公開が成功。Android 14実機へのインストールも確認済み。アプリ内からの次バージョン上書きは未検証。
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

1. 既存の公開ソースリポジトリ `mibesamiti-png/chappy-player` で作業する。初回導入の場合はこのリポジトリを取得する。
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

**正式版は固定署名付きAPK**。初回v0.2.0 (Build 5) のビルド・署名検証・公開・端末へのインストールを確認済み。
デバッグ版との署名は異なるので、初回移行はアンインストールが必要になる場合がある。一方、正式署名版同士は同じアプリID・署名でビルド番号が増えればAndroid標準インストーラーから上書き可能。

**上書き更新の実機成功はまだ未確認**。更新の前に必ず保存データをバックアップし、`.chappy` 本体も保管すること。失敗しても、既存アプリをいきなりアンインストールしないこと。

新リリースはこの公開ソースリポジトリの `Publish Signed APK Updates` を**手動実行**する。生成APK・更新JSONのみを配布専用リポジトリに保存し、秘密の署名鍵やトークン、個人データは含めない。

## 保存データのバックアップと復元（開発中）

ホーム画面の「保存データをバックアップ」「保存データを復元」から利用する。

- バックアップは `.chappybackup`（UTF-8 JSON）形式。最大12MiB／100アプリ、1アプリ当たり1MiB。
- 保存するのはアプリ別のJSON保存データのみ。**`.chappy` 本体、旧版、デバッグログは含まない**。本体は別途保管すること。
- Androidのファイル保存画面で、端末の外部ストレージやクラウドなどにバックアップを保存する。
- 復元前にアプリID・件数・作成日時を確認してから実行。同じIDのデータは上書きする。
- 強制終了に備え、復元中は旧データを一時的に退避し、次回起動時に中断された復元を取り消す。
- **暗号化なし**。メモ本文などが含まれるため、バックアップファイルを他人へ公開しないこと。

バックアップ→APKアンインストール→新APKインストール→復元→`.chappy` の再インポート、の順でデータ移行が可能（実機動作は未検証）。

## 固定署名APKのビルド・更新

公開版のビルドは `.github/workflows/publish-signed-apks.yml` を実行する。
この公開GitHubリポジトリの `Actions → Publish Signed APK Updates → Run workflow` で `version` と `release_notes` を入力する。

- `CHAPPY_KEYSTORE_B64`、`CHAPPY_STORE_PASSWORD`、`CHAPPY_KEY_PASSWORD`、`CHAPPY_KEY_ALIAS` はリポジトリの非公開 **Actions Secrets** に登録済み。ソースが公開でもSecretsの内容は公開しない。
- `CHAPPY_RELEASE_CERT_SHA256` は **Actions Variables** に登録済み。実際の秘密鍵と生成APKの両方をこの証明書指紋と照合する。
- `CHAPPY_PUBLISH_TOKEN` は公開配布専用リポジトリにしか書き込めないトークンとして **Actions Secrets** に登録済み。
- Secrets・署名鍵・トークンはチャットやソースに貼り付けない。
- 今後の更新でも **同一の署名鍵**を使う。署名鍵とパスワードは安全な場所にバックアップする。

初回更新の手順は [Android上書き更新実機チェックリスト](docs/android-update-smoke-test.md) を参照。

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
- ブリッジは storage/info/log と、マニフェスト宣言・個別許可が必要なカメラ/マイクのWeb標準APIを提供する。WebViewマイクは一部端末で失敗するため、ネイティブ AudioRecord はPR #29で開発中（まだ正式リリースには未反映）。Bluetooth・バックグラウンド通信は未実装。
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

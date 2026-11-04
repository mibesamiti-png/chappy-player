# Chappy Player 公開APK配布の初期設定

2026-11-04。ソースコードの`mibesamiti-png/chappy-player`は**非公開のまま**にする。

## 配布専用の公開リポジトリ

新規作成するリポジトリは **`mibesamiti-png/chappy-player-updates`**。
GitHubの「New repository」から作成し、必ず以下を選ぶ。

- Repository name: `chappy-player-updates`
- Visibility: **Public**
- Initialize with a README: **ON**（default branchが `main` であること）

**公開するもの**：署名付きの`ChappyPlayer-arm64-v8a.apk`等、
リリースノート、バージョン情報`update.json`、配布リポジトリの説明。
**公開しないもの**：Flutter/Dart/Kotlinのソース、秘密の署名鍵、
GitHubトークン、デバッグログ、個人メモデータ。

注意：APKは逆解析可能。ソースのリポジトリを非公開にしても、
配布したAPK内の実装や素材を完全に隠せるわけではない。

### 公式のダウンロードURL

更新JSON（常に同じURL）：
`https://raw.githubusercontent.com/mibesamiti-png/chappy-player-updates/main/update.json`

完成した各APKは**GitHub Releases**のリリースファイルとして配布する。
例：
`https://github.com/mibesamiti-png/chappy-player-updates/releases/download/v0.2.0-b1/ChappyPlayer-arm64-v8a.apk`

この例URLは**セットアップ後にのみ存在する**。現時点では実際のAPKの配布先ではない。

## 固定署名の設定（初回だけ）

ユーザーが管理する安全な環境で、Androidの署名キーストアを1回生成する。
例：Java JDKの `keytool`。実際に作る際は有効期限とパスワードを確認する。

```bash
keytool -genkeypair -v -keystore chappy-release.jks \
  -storetype PKCS12 -keyalg RSA -keysize 3072 -validity 10000 \
  -alias chappy
```

`chappy-release.jks`は**端末以外にも安全に複数バックアップ**し、
パスワードはパスワードマネージャー等へ保管する。
**署名鍵は一度もChatGPTのメッセージやGitHubのIssueに貼らない。**

キーストアのBase64を生成する（シェル例）：

```bash
base64 -w 0 chappy-release.jks > chappy-release.b64
```

GitHubの非公開開発リポジトリで
`Settings → Secrets and variables → Actions → Repository secrets`を開き、
次の4件を登録する。

| Secret名 | 内容 |
|---|---|
| `CHAPPY_KEYSTORE_B64` | キーストアのBase64全体 |
| `CHAPPY_STORE_PASSWORD` | キーストアのパスワード |
| `CHAPPY_KEY_PASSWORD` | 署名鍵のパスワード |
| `CHAPPY_KEY_ALIAS` | `chappy` |

さらに証明書のSHA-256フィンガープリントを取得：

```bash
keytool -list -v -keystore chappy-release.jks -alias chappy
```

出力に表示される証明書SHA256の64桁16進数
（コロンを除いたもの）を、同じリポジトリの
`Settings → Secrets and variables → Actions → Variables` に
`CHAPPY_RELEASE_CERT_SHA256`として登録する。
この公開可能なフィンガープリントを使い、今後の署名鍵の意図しない
入れ替わりを公開前に強制停止する。

## 公開先専用のGitHubトークン（初回だけ）

GitHubの `Settings → Developer settings → Personal access tokens → Fine-grained tokens`
でトークンを作る。

- Repository access: **Only select repositories**
- 選択: `mibesamiti-png/chappy-player-updates` **のみ**
- Repository permissions: **Contents: Read and write**
- 有効期限は長すぎない設定にして、期限切れ時は更新する

このトークンは秘密の署名鍵とは別物で、公開GitHubリポジトリに
APKと`update.json`を書き込むため**だけ**に使う。
`mibesamiti-png/chappy-player`（非公開の開発リポジトリ）の
`Settings → Secrets and variables → Actions → Repository secrets`へ
`CHAPPY_PUBLISH_TOKEN`という名前で登録する。
**トークンをチャットやソースコードに貼り付けない。**

## 公開操作

上記3点（公開配布リポジトリ・固定署名・トークン）が揃ってから、
**非公開開発リポジトリ**の`Actions → Publish Signed APK Updates → Run workflow`を実行する。

入力例：

- `version`: `0.2.0`
- `release_notes`: `バックアップと更新機能の修正`

ワークフローが**自動的に**実行する作業：

1. 非公開のソースコードをCI内でチェックアウトし、Flutterテストを実行。
2. 固定の署名鍵でARM64 / ARM32 / x86_64のリリースAPKを生成。
3. Android公式の`apksigner`で署名が正しいか確認し、
   登録した証明書SHA-256と完全一致するか検証。
4. **APK3個だけ**を公開リポジトリのGitHub Releaseにアップロード。
5. APKのハッシュ・サイズ・バージョンを自動計算して`update.json`を生成。
6. `update.json`を公開リポジトリの`main`へ書き込み。
7. 公開済みのビルドより古い番号なら更新JSONの書き換えを拒否。

ビルドが途中で失敗した場合、`update.json`は変更しない。
途中でリリースだけ残った場合も、更新フィードは旧版を指したままで安全。
**GitHub Actionsの実行ごとに別のデバッグ署名で公開する運用はしない。**

## スマホ側の初回移行と今後の更新

今使っているテスト用デバッグAPKと、初回の固定署名APKは
**署名が異なる可能性が高い**ため、最初の一回だけアンインストールが
必要になる場合がある。

1. まず現在のChappy Playerでバックアップ（0KBではない）を作成し、
   **復元できること**を確認。ミニアプリ本体`.chappy`も保管する。
2. 固定署名版の初回インストール。アンインストールが必要な場合、
   アプリ内データは消えるため前段のバックアップが必須。
3. バックアップを復元する。
4. 同じキーストアで次のビルドを公開する。
5. Chappy Playerの更新画面で「最新版を確認 → ダウンロードして更新」を押す。
6. Android標準のインストール確認に同意する。**通常はアンインストール不要。**
7. メモが残っていることを確認する。

**実機でのアプリ内更新成功はまだ未確認。** 初回の上書きテストは
重要でないダミーデータから始めること。

## 安全性の注意

- 更新JSONは公開HTTPSの固定アドレスで取得し、ダウンロードしたAPKのSHA-256を検証。
- GitHub Releasesの正規CDNへのHTTPSリダイレクトのみ許可。
- 更新前にAndroidがAPKのアプリID・署名証明書・新しいビルド番号を確認。
- アプリはAndroidのインストール確認画面を開くだけ。無承認の上書きはしない。
- ソースの非公開設定は変更しない。
- 公開リリースにはデータ・デバッグレポート・署名鍵を絶対含めない。

# NETLAB-03B-2 — Android KeyStore / Windows DPAPI 端末IDの準備段階

**状態：ソース試作。永続ペアリング・相互認証・PC操作・通信量共有は未実装。正式APK/Stable配布には未反映。**

関連：[Issue #56](https://github.com/mibesamiti-png/chappy-player/issues/56)・[Network Lab roadmap](https://app.notion.com/p/410948b74937818f8eea-ca22609052b2)・[既存の一度きりQR接続確認](network-lab-qr-bootstrap.md)。

## なぜこの段階が必要？

現在の `Start-ChappyPairing.cmd` は、PCが起動するたびに新しい一時TLS証明書を使って**一度だけ確認**する仕組み。再接続の信頼根拠は保存しておらず、これを「ペアリング済み」と呼ぶのは誤り。

永続的な相互認証を後から安全に追加できるように、**双方で独立した端末ID鍵を明示的に作成・確認・削除できる土台**を用意した。鍵の存在のみで権限が生まれることはない。mDNSで見つかった名前を信頼しないことも維持する。

## Windows側：同じWindowsユーザーのDPAPI

- `ChappyCompanion.exe --identity-status`：公開鍵のSHA-256指紋を表示。秘密鍵・ユーザー名・ホスト名・ネットワーク情報は表示しない。**鍵がなければ作らない**。
- `ChappyCompanion.exe --identity-create`：ユーザーが明示して実行したときだけP-256 EC署名鍵ペアを1つ生成。既存の秘密鍵を上書き・更新しない。
- `ChappyCompanion.exe --identity-revoke`：本人がコンソールで大文字 `REVOKE` と入力した場合のみ保存鍵を削除。取り消し不可、再作成した場合は公開指紋が変わる。
- 秘密鍵のPKCS#8 DERは**現在ログインしているWindowsユーザーに紐づくDPAPI `CryptProtectData`** で保護してから `%LOCALAPPDATA%\ChappyCompanion\device-identity-v1.dpapi` に保存する。 `CRYPTPROTECT_LOCAL_MACHINE`（同一PCの全ユーザーで復号可能）は**使用しない**。通常は同じログオン資格情報が必要だが、ローミングプロファイル等のWindows管理条件による例外がある。DPAPIファイルは一般的なバックアップ/クラウド同期用に持ち出さない。
- 保存するのは暗号化された秘密鍵のみ。コードに秘密鍵は埋め込まず、PR、ログ、Notionにも書かない。
- これらのコマンドでは**mDNS広告、TLSサーバー、ファイル転送、通信監視、遠隔操作を開始しない**。従来の `--start` / `--start --pair --qr` と同時指定できない。
- PCの既存QR接続確認は**従来どおり一回限り**で、新しい永続鍵とまだ結び付いていない。

## Android側：Android KeyStore

- **Network Lab →「PC連携用の端末キーを準備・削除」** のボタンから、公開鍵のSHA-256指紋を確認。未作成状態では勝手に鍵生成しない。
- 「端末キーを作成」→説明を読み、**もう一度作成を承認** → Android KeyStoreにP-256署名鍵ペアを生成。 `KeyProperties.PURPOSE_SIGN` と `DIGEST_SHA256` に限定。公開鍵SPKI DERのSHA-256を表示。秘密鍵バイト列は取得・書き出しできず、Flutterや`.chappy` JSに渡さない。
- 「この端末の秘密鍵を削除」→**もう一度削除を承認** → Keystoreの登録エントリー削除。端末を再セットアップした場合・アプリ再インストールでは端末IDが変わる可能性がある。
- ネイティブ操作は信頼済みFlutterホストの`dev.chappy.player/network_lab` MethodChannelのみ、アプリが前面にある場合に限定。**ミニアプリJSや外部WebViewへ鍵・署名APIは公開しない。**
- Android端末によって鍵のハードウェア保護有無は異なる。ハードウェアバックアップや端末移行機能を保証しない。現在は署名要求APIそのものを提供せず、実際のPC相互認証はまだ行わない。

## 次に必要な実装（Issue #56に残す）

1. QRで読み取る一時TLS証明書の検証とPCの**継続公開鍵**の結び付け、双方の独立した人手承認。QRの指紋と公開端末IDの混同を防ぐ。
2. 公開鍵の交換に加え、双方が**チャレンジへ署名して秘密鍵所有を証明**する標準のP-256 ECDSA相互認証。nonce、期限・再利用防止、セッション証明とTLSピン留め。認証コードだけを秘密として扱わない。
3. 双方の信頼済み端末**公開鍵リストと解除/失効**。秘密鍵・信頼済みレコードを永続保護したうえで、解除後の再接続を確実に拒否。PC／Android双方が自分側で取消可能なUIを用意。
4. Wi-Fi変更、時間ずれ、複数PC、OS再インストール、署名鍵ローテーション、Android17のLAN接続許可・検証、期限切れ/拒否/リプレイなどの攻撃テスト。
5. ここまで実機2台で通ってから、**ユーザーが明示許可したPCの通信量**を読み取り専用で表示する機能へ進む。PC操作やファイル転送は別の明示権限と設計を必要とする。

## 品質と公開の区別

- **Windows CI（Windows-latest）**：実DPAPIで生成・再読込・上書き拒否・破損検出・明示的削除・ローテーションを検証。通常のCompanion EXEが勝手に広告しないことも維持。
- **Android CI**：Flutterの確認UIのキャンセル時にネイティブ鍵操作が呼ばれないテスト、公開指紋の入力検証、Kotlinソースの鍵API/信頼境界チェック、AndroidデバッグAPKビルド。
- CI上で端末キー生成が可能でも、**本物のAndroid KeyStoreハードウェアとWindows PCとの接続が成功した証明ではない**。Android端末・Windows実機で鍵生成/再起動/削除を個別に確認する必要がある。
- **正式署名APK、Stableカタログ、バックアップ、既存のユーザーデータは変更しない**。Windowsは未署名プレビューEXE、Androidは開発ビルドにのみ反映。正式公開にはユーザー指示と実機QAが必要。

公式参考：[Android KeyGenParameterSpec](https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec) ／ [Windows CryptProtectData](https://learn.microsoft.com/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata) ／ [Windows CryptUnprotectData](https://learn.microsoft.com/windows/win32/api/dpapi/nf-dpapi-cryptunprotectdata)。

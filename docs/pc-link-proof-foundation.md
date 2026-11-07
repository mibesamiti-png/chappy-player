# NETLAB-03B-3 — PC / Android P-256 署名による本人鍵の所有証明（部品段階）

**状態: ソース実装 + 自動テスト対象。まだPCペアリングではない。正式署名APK未公開・実機未検証。**

関連: [端末キー準備段階](pc-link-identity-foundation.md) / [Issue #56](https://github.com/mibesamiti-png/chappy-player/issues/56) / [一度きりQR招待](network-lab-qr-bootstrap.md)

## 今回できるようにしたこと

- Windows: examples/windows_companion/identity_proof.py に、既存のWindowsユーザー限定DPAPI保管済みP-256鍵を使って、指定の一時チャレンジにECDSA-SHA256署名する**オフライン関数**を追加。鍵がない場合は失敗し、自動生成しない。公開SPKI DERと署名はbase64で返すが、秘密鍵を返さない。
- PC側とAndroid側で、同一の厳密な**署名対象バイト列**を定義。役割（pc/android）、一時招待ID、短命TLS証明書の指紋、接続相手の公開鍵指紋、検証側が発行した32バイトnonce、期限を署名対象に含める。
- Android: NativePcProof.kt に、既存AndroidKeyStoreのP-256鍵を使う署名関数と、相手のP-256署名を検証する関数を実装。**ホスト内部ライブラリのみ**で、MainActivityのMethodChannel、Flutter画面、.chappy JS、LANソケットにはまだ接続しない。
- 検証は、署名者の期待公開鍵指紋を**受信したデータ以外の信頼できる経路**から得た場合のみ成功と判定。SPKIのSHA-256が一致し、P-256曲線で、期待したセッション値・署名がすべて一致することを要求。
- 異なる役割、TLS証明書、招待ID、相手鍵指紋、nonce、期限、署名・公開鍵の改ざん、不正なBase64、期限切れ、10分を超える未来期限を拒否。

## 共通署名メッセージ形式

厳密なASCII / UTF-8（全フィールド英数字、改行LF、最後にもLF）:

~~~text
CHAPPY-NETLAB-03B-PROOF-V1
role=pc
invitation=<16 random bytes as 32 lowercase hex>
tls=<temporary TLS certificate SHA256 as 64 lowercase hex>
peer=<other device SPKI SHA256 as 64 lowercase hex>
nonce=<verifier-generated 32 random bytes as 64 lowercase hex>
expires=<Unix seconds in decimal>
~~~

役割 android はAndroid側の署名だけで使用。短い比較コードは**人の確認用**で、認証秘密としては使用しない。TLS pin（証明書の指紋）と端末公開鍵指紋（SPKIの指紋）は別物で、混同しない。

署名データは algorithm、spki、signature の3項目のみ。公開SPKIと署名は標準のpadding付きBase64。リクエストやレスポンスに秘密鍵は入らない。

## なぜまだ相互認証が完成していないのか

- **今回の署名関数はLAN通信路へ接続していない。** 既存QR-v2確認フローにも組み込んでおらず、UIから署名はできない。アプリが勝手に署名を始めない。
- オフラインの署名検証だけでは**初めて出会う相手を信頼できない**。双方が意図した相手の公開鍵を、現物QR・PC画面の指紋・双方の承認を通じて確認しなければならない。
- 署名は新鮮なnonceとセッション内容に結び付くが、**nonceを一度だけ使用済みにするのは将来のペアリングセッション管理側の責務**。この関数自体にはリプレイ履歴を持たせない。
- 信頼済み相手公開鍵の登録・ユーザーUI・失効情報の伝搬・相互チャレンジの送受信・自動再接続・PCファイル/操作/通信量取得は未実装。
- Android側の関数はホスト内部の保留部品。実際に呼ぶ前に、前面状態・手動確認・署名利用目的・期限・取り消しを管理する状態機械が必要。単なる任意データ署名APIをJSへ公開しない。

## 検証とリリース安全性

- python tools/test_pc_proof.py: 共通メッセージの固定形式、ECDSA署名の成功・改ざん拒否、期限・型の拒否。Windows CIではDPAPIを使用した鍵の実生成→署名→失効後の拒否も実行。
- python tools/test_pc_proof_contract.py: Android KeyStore署名部品の存在と、Flutterホスト・ミニアプリJSへの**非公開**を検証。
- Android CIで tools/patch_android.py が新しいKotlinクラスをインストールしたうえでdebug APKをビルド。コードのコンパイル成功と、実機AndroidKeyStoreが動作することは別。
- production署名設定、releaseワークフロー、既存のQR接続、ゲームサーバー用HTTPS/WSS、通信量グラフ、Stable/Debugカタログ、端末内の既存データは変更しない。

## 次のステップ（NETLAB-03B-4以降）

1. アプリ前面の専用ペアリング画面からだけ、既存のピン留めTLS QR招待内で**一度きりの相互チャレンジを送受信**。Android/Windows双方の署名を検証し、既存のPC側YESとスマホ側の明示承認を維持する。
2. 期限切れ・片側拒否・タイムアウト・再送・再利用・ネットワーク変更・二重ペアリングで確実にキャンセル。署名対象に使ったnonceはセッションで一度だけ消費する。
3. 双方の端末公開鍵の信頼リスト、独立した明示解除、鍵更新と登録破棄。通信機能は読み取り専用から別権限で導入。
4. WindowsとAndroid実機のWi-Fi/QR/キーストア/DPAPI両方のQAが通るまで正式APKを公開しない。

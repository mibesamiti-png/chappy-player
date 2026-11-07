# NETLAB-03B-4 — QR-v3のPC↔Android一時相互認証プレビュー

**状態: 開発ソースのみ。実機未確認・正式署名APK未公開。** 永続登録済みペア、PC操作、ファイル転送、通信量取得、自動再接続ではない。

## 手動操作（管理する同一LANでのみ）

1. Windows Companionプレビューのコマンドラインで、端末鍵がない場合にのみ明示的に ChappyCompanion.exe --identity-create を実行。Windowsの現在のユーザーのDPAPIで秘密鍵を保護する。通常起動では自動生成しない。
2. ChappyCompanion.exe --start --pair --qr --identity-pair をPCで明示実行。短命のQR-v3をPC画面に表示。旧QR-v2（--start --pair --qr）とv1手入力はそのまま。
3. Android Debugの Network Lab → PC連携用の端末キーを準備・削除 でAndroid KeyStore鍵を作る。すでにあれば保持する。Network Lab → PC・ワークステーション → 探索開始 → 自分のWindows Companionを選択 →QR読取。
4. スマホとPCに表示された6桁のコードを照合する。PCにはスマホの公開鍵指紋が表示される。意図した相手の場合だけPCでYESを入力する。
5. PCが自身の署名を返し、AndroidがQRのPC公開鍵指紋、TLS証明書、一時招待、スマホ公開鍵、乱数、有効期限を検証する。
6. Androidで独立した確認ダイアログから「この1回だけ署名する」を押した場合だけ、Android KeyStoreでPC発行のチャレンジに署名を返す。Windowsが検証して、今回の相互鍵所有確認が成功。秘密鍵は送らず、信頼リストにも登録しない。

## QRと通信

- v1: 手入力の一時TLS証明書指紋+PCのYESのみ。端末鍵の証明はない。
- v2: chappy-pair://v2、短命QRの招待ID+一時TLSピン+PCのYESのみ。端末鍵の証明はない。
- v3: chappy-pair://v3?ip=...&port=...&fp=...&inv=...&exp=...&pc=...。fpは一時TLS証明書SHA256。pcは**PCの永続端末公開鍵SPKI SHA256**。どちらも64桁小文字hexで混同しない。invは128ビットランダム値。発見したNSD機器の名前を認証の根拠にしない。QRのIPとポートは選択した発見先と一致必須。
- /v3/identity-begin（ピン留めTLS）: Androidはphone_nonce（32バイト）、phone_fp、招待を送信。PCは招待を1回だけ消費して本人のYESを要求、DPAPI鍵でPC側の署名を生成。新しいPCのpc_nonce（32バイト）と最大90秒の期限を返す。
- /v3/identity-finish（ピン留めTLS）: AndroidがPC署名を検証し利用者が再承認したときだけAndroid KeyStore署名を送る。Windowsは登録された今回のphone_fp、招待、TLSピン、nonce、署名を検証。成否を問わずチャレンジは二度と使えない。
- 署名メッセージ形式は pc-link-proof-foundation.md と共通。PCとAndroidは別role、別乱数。短い6桁コードは人間の確認用であり認証秘密ではない。
- PCへの要求上限2048バイト、Android応答上限2048バイト。PC側ではTLSハンドシェーク/接続数制限を維持。Androidでは証明書ピン不一致を拒否。

## 安全性と未実装

- Windowsは常時起動しない。所有者の明示コマンド/YESが必要。Androidは前面、Wi-Fi/Ethernet、QR、明示承認が必要。NativePcProofは信頼済みFlutterホストの限定MethodChannelからだけ呼び出し、.chappy JSへは公開しない。
- 期限切れ、異なるTLSピン、QR招待改ざん、異なる公開鍵、役割反射、別nonce、署名改ざん、重複試行を拒否。PC/スマホどちらかが拒否したら成功とはしない。
- **永続的なペアリングは未実装。** 信頼済み端末の登録・解除、失効・鍵更新と再登録、利用権限の分離は次段階。PC操作、通信量監視、ファイル転送を許可しない。
- WindowsとAndroidの実機でQRの読み取り、ファイアウォール、PCとスマホの両側拒否、画面ロック、Wi-Fi切断、ゲストWi-Fi、複数PC・端末、時刻ずれ、Android KeyStoreの機種依存挙動を確認してから正式版を検討する。
- v1/v2への自動ダウングレードなし。正式署名APK、Stable/Debugカタログ、更新JSON、既存ユーザーデータ、アプリのパッケージIDと署名は変更しない。

## QR-v3 HTTP要求の追加検証（4B-3）

Windows側の2段階認証で受け取るJSONは、オブジェクト内の同名キーの重複をネスト階層も含めて拒否。これにより、同じ protocol や phone_proof を複数指定して解釈を曖昧にするリクエストが、承認・署名前に拒否される。

Content-Lengthの複数指定、過度に長い数値、Transfer-Encodingの混在、重複Content-Type、不完全なJSON本文も拒否する。期限内の正しい初回QR招待は、このような不正パースによって消費しない。元のv1/v2の受信・仕様には変更なし。

## テスト

- Windows: python tools/test_identity_pairing_v3.py — 2段階の署名検証、再利用/期限/改ざん拒否、PCでの人手承認、隔離localhost HTTPテスト。
- Android: flutter test — QR-v2/v3と署名アダプタの入力検証。python tools/test_pc_proof_contract.py — ネイティブ前面/Wi-Fi制限とミニアプリJS非公開。Flutter analyze、Kotlin/Android Debug APKビルドも同一PRで確認。
- 自動テスト成功と物理2台のWi-Fi実機でペアリング成功は別。署名済み正式APKはユーザーの明示指示と実機QAなしに公開しない。

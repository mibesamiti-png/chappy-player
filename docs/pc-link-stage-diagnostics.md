# NETLAB-03B — 相互認証の段階別診断（開発プレビュー）

QR-v3で通信や相互署名に失敗したとき、Androidホスト画面には固定の段階コードと[安全なエラー分類](pc-link-safe-pairing-errors.md)を併記する。**コードは直前に試みていた処理を示し、失敗原因の確定を意味しない。**

| 段階コード | 意味 |
| --- | --- |
| STAGE-QR | QR、指紋、招待期限など接続前の入力・事前確認 |
| STAGE-NET | LAN状態、TLS接続、PCからの初回応答 |
| STAGE-PC | PCのP-256公開鍵署名を検証 |
| STAGE-PHONE | Android利用者の承認と端末鍵での署名 |
| STAGE-FINISH | Android署名提出後、PCの最終確認 |

例：`失敗した段階: LAN・TLS接続とPC応答 [STAGE-NET]。接続確認に失敗 [PAIR-TIME]：...`

実装は試行ごとのメモリ内変数のみ。段階情報は秘密鍵、QR招待ID、nonce、公開鍵指紋、TLS証明書、IPアドレス、署名、例外全文を保存・送信・表示しない。ログやディスクへの永続化は追加しない。認証判定、QRのワンタイム消費、同意、暗号鍵操作、既存v1/v2通信方式は変えない。v1/v2の試行では存在しないPC署名やスマホ署名段階を表示しない。

## 検証

- `flutter test test/pc_pairing_stage_test.dart`: 各段階コードの安定性と固定ラベル。
- `flutter test test/companion_qr_lifecycle_test.dart`: QRの使用済み処理と、ネイティブ例外がQR段階で安全な表示になること。
- `flutter analyze && flutter test`: 既存テストも含む回帰確認。
- [実機QAマトリクス](pc-link-two-device-qa-matrix.md)のQA-01〜05で、PC側拒否・画面遷移・ネットワーク断に対する表示を照合する。

正式署名APKの公開、PC操作許可、恒久ペア登録を含まない。**Android↔Windows物理2台での表示・動作確認は未実施。**

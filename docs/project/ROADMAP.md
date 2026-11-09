# Chappy Player — 次に実装するロードマップ

更新: 2026-11-09。**R4Cのソース実装・Quick/Windows CIは完了、次はR5**。R4CのPC状態取得は一回限りのプレビューで、実際のAndroid↔Windowsの実機QAは未実施（0/15）。

| 順番 | バッチ | 主な内容 | 本体/ミニアプリ | 現状 |
| --- | --- | --- | --- | --- |
| 1 | PC Link R4B | 期限/双方同意/権限分離、Python/Dart合同の127.0.0.1通信テスト | WindowsとDartの**テスト専用**モデル。新規Debugミニアプリなし | **ソース統合・CI成功（実PC接続なし）** |
| 2 | PC Link R4C | QR-v3署名/TLSピン＋双方別承認の1回限定PC状態取得（CPU/RAM/起動時間） | 本体ホスト画面＋Windows Companion。新規Debug Labなし | **ソース統合・CI成功、実機QA未実施** |
| 3 | PC Link R5 | 明示許可したファイルのチャンク送受信、上限/SHA-256、進捗/キャンセル/復旧 | 本体＋Companion、**PC Transfer Lab 新規** | **次・未着手** |
| 4 | PC Link R6 | 明示的承認を伴う限定リモート操作（まず音量・メディア操作、次に入力系を個別設計） | 本体＋Companion、**PC Control Lab 新規** | 未着手 |
| 5 | Network R7 | Browser/LAN診断、ブラウザUI、通信診断 | 本体API、**Browser Lab 新規**、Game Server Lab拡張 | 未着手 |
| 6 | Game R8 | セッション・ルーム同期・Ping・承認済みゲームサーバーへの通信 | Game Server Lab拡張 | 未着手 |
| 7 | Media R9 | 録画耐久・安全な復旧、Androidの制約と許可に合うバックグラウンド動作 | Recorder / Media Lab拡張 | 未着手 |
| 8 | Platform R10 | API対応状況・権限明示・開発者向け検査と互換性 | **API Test Lab 新規** | 未着手 |
| 9 | Release Gate | 全体の回帰・2台実機QA・署名/保存データ継続・公開判断 | 既存Debug Lab活用 | 毎段階で実施、Stableは別承認 |

## 次バッチ：PC Link R5 の8タスク（未着手）

1. **転送権限分離**：PC Link本人確認・`pc.status.read`とファイルの新規権限を完全に分離し、PC/Android双方の明示承認。
2. **ファイル境界**：所有PC側の利用者が明示選択した対象/保存先のみ。パストラバーサルと任意パス取得は拒否。
3. **信頼性**：チャンク転送、サイズ・容量上限、SHA-256チェック、重複/再使用禁止。
4. **中止**：切断・権限取消・期限切れで停止し、一時ファイルと部分転送を安全に扱う。
5. **Androidホスト**：許可したファイルだけを選択・送受信・保存、進捗とエラーを表示。
6. **新規Debugミニアプリ**：PC Transfer Lab。ネイティブ権限をJavaScriptに直接与えず、ホスト承認で仲介する。
7. **攻撃テスト**：不正パス・過大転送・署名再利用・同時要求・接続中断・権限漏れ。
8. **品質/引き継ぎ**：Quick CI/Windows CIとプレビュー成果物、R4C実機QA別記録、GitHub/Notion更新。

**R5も実機テスト前に実装できる部分を優先する。ただし安全性を犠牲にしてPCの全ファイルを開放しない。**

## R4C完了（ソース・CI、実機未検証）

- [PR #99](https://github.com/mibesamiti-png/chappy-player/pull/99) をmain統合（`cc4a692b0d4c3e687e2344f399ff7111811f9e34`）。
- [Quick CI](https://github.com/mibesamiti-png/chappy-player/actions/runs/42587043221) と [Windows CI](https://github.com/mibesamiti-png/chappy-player/actions/runs/42587042801) 成功。
- QR-v3で実際に検証したAndroid公開鍵・QR招待・TLSピンに限定し、`status=1`とWindowsの明示起動がある場合だけ1回status権限を要求。
- PC YESと別のWindows STATUS承認、Androidの別ダイアログ・新規署名、1回限りのnonce・期限・再使用拒否。CPU/RAM/uptimeをWindows APIから取得するコード。
- Windows/Androidの2台実機QA 0/15未実施、Stable/APK/公開ミニアプリ更新なし。[R4C詳説](../pc-link-r4c-status-once.md)。

## 完了履歴：PC Link R4B の8タスク

1. `PC-R4B-01`: ワンタイム認証と、後続のセッション候補を明確に分ける期限・終了・キャンセル状態機械。
2. `PC-R4B-02`: 相互署名が通っても権限が**ゼロ**のモデル。別途明示承認が必要なCapability構造。
3. `PC-R4B-03`: 読み取り専用PC状態APIの権限スコープ・可視化・同意の仕様。
4. `PC-R4B-04`: Windows/Dartでプロトコル項目・上限・安全なエラーコードを一致させる。
5. `PC-R4B-05`: 拒否、期限切れ、重複、競合、中断、誤署名の回帰テスト。
6. `PC-R4B-06`: 隔離loopbackでのクロス言語プロトコル統合テスト。これを実機PASSにしない。
7. `PC-R4B-07`: QR/公開鍵指紋/履歴/JSに関する権限隔離・秘密非公開の回帰。
8. `PC-R4B-08`: Quick CI + Windows CI、統合後のSTATE/HANDOFF/Notion更新。

**明確に後回し**: Android↔Windows実機15ケースのQA、永続的な自動再接続、PCファイル/任意コマンドアクセス、正式署名APK公開。前倒し実装可能なオフライン基盤は先に作るが、認証の安全境界は省略しない。

## 現状・履歴

- R4B PR #97は [Quick CI](https://github.com/mibesamiti-png/chappy-player/actions/runs/42468375810) と [Windows CI](https://github.com/mibesamiti-png/chappy-player/actions/runs/42468375793) 成功で main `ad95401f86362c760139990241a7546984c809f6` に統合済み。実PC接続権限は追加していない。

- R4A PR #95 は [Quick CI](https://github.com/mibesamiti-png/chappy-player/actions/runs/42443650137) と [Windows CI](https://github.com/mibesamiti-png/chappy-player/actions/runs/42443650188) 成功でmain統合済み。
- 2026-11-08、ユーザーから修正版Debug APKの**起動成功**報告。ただしPC Link両端末QAは未実施。
- [PC Link QR-v3](../pc-link-mutual-qr-v3.md) / [2台実機QA](../pc-link-two-device-qa-matrix.md) / [過去のNative API構想](../native-capabilities-roadmap.md)

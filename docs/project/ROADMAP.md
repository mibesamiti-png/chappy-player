# Chappy Player — 次に実装するロードマップ

更新: 2026-11-08。R4Bまでのソース実装・CIは完了、**次はR4C**。なおR4Bはオフライン試験専用であり本番機能や実機QAを済ませた意味ではない。

| 順番 | バッチ | 主な内容 | 本体/ミニアプリ | 現状 |
| --- | --- | --- | --- | --- |
| 1 | PC Link R4B | 期限/双方同意/権限分離、Python/Dart合同の127.0.0.1通信テスト | WindowsとDartの**テスト専用**モデル。新規Debugミニアプリなし | **ソース統合・CI成功（実PC接続なし）** |
| 2 | PC Link R4C | QR-v3/TLSに結び付いた短命接続権限、双方承認、実際のPC状態の読み取り専用表示 | 本体ホスト画面＋Windows Companion。新規Debugミニアプリなし | **次・未着手** |
| 3 | PC Link R5 | 認証後のユーザー指定ファイル転送、サイズ/チェックサム/進捗/キャンセル・復旧 | 本体＋Companion、**PC Transfer Lab 新規** | 未着手 |
| 4 | PC Link R6 | 明示的承認を伴う限定リモート操作（まず音量・メディア操作、次に入力系を個別設計） | 本体＋Companion、**PC Control Lab 新規** | 未着手 |
| 5 | Network R7 | Browser/LAN診断、ブラウザUI、通信診断 | 本体API、**Browser Lab 新規**、Game Server Lab拡張 | 未着手 |
| 6 | Game R8 | セッション・ルーム同期・Ping・承認済みゲームサーバーへの通信 | Game Server Lab拡張 | 未着手 |
| 7 | Media R9 | 録画耐久・安全な復旧、Androidの制約と許可に合うバックグラウンド動作 | Recorder / Media Lab拡張 | 未着手 |
| 8 | Platform R10 | API対応状況・権限明示・開発者向け検査と互換性 | **API Test Lab 新規** | 未着手 |
| 9 | Release Gate | 全体の回帰・2台実機QA・署名/保存データ継続・公開判断 | 既存Debug Lab活用 | 毎段階で実施、Stableは別承認 |

## 次バッチ：PC Link R4C の8タスク（未着手）

1. 本物のQR-v3署名成功・ピン留めTLSを認可処理に結合（テスト用boolを認可と混同しない）。
2. 短命接続セッション、期限・再使用防止・切断時失効を両側で保証。
3. 読み取り専用PC状態スコープへ、PC/Android双方の明示的承認。
4. Windowsの実PC状態を安全に取得し、非対応・欠測を正確に表現。
5. Androidホスト画面でPC状態、権限、失敗・オフラインを安全に表示。
6. TLS/署名/期限/二重要求/中断/鍵変更の合同回帰。
7. .chappy JSへのPC操作・秘密・信頼素材の非公開をテスト。
8. Quick/Windows CI + Debug/実機判定の区別と引き継ぎ更新。

**注意:** R4Bで作ったオフラインモデルは実行中のPC通信に繋がっていない。本人確認成功をネットワーク権限として転用するのはNG。

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

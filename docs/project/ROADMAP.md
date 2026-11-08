# Chappy Player — 次に実装するロードマップ

更新: 2026-11-08。これは**将来計画（未実装）**を表す。過去のR1/R2/R3/R4Aなど完了済みバッチの機能と混同しない。

| 順番 | バッチ | 主な内容 | 本体/ミニアプリ | 現状 |
| --- | --- | --- | --- | --- |
| 1 | PC Link R4B | 認証済みセッション状態機械・期限・明示的な読み取り権限・Dart/Windows通信契約・仮想統合テスト | Android本体＋Windows Companion。新規Debugミニアプリなし | **次・未着手** |
| 2 | PC Link R4C | ユーザー承認済みPCの読み取り専用状態（オンライン/負荷/通信量の安全な集計）と表示 | 本体ホスト画面、必要なら専用PC Status Lab（最初は不要） | 未着手 |
| 3 | PC Link R5 | 認証後のユーザー指定ファイル転送、サイズ/チェックサム/進捗/キャンセル・復旧 | 本体＋Companion、**PC Transfer Lab 新規** | 未着手 |
| 4 | PC Link R6 | 明示的承認を伴う限定リモート操作（まず音量・メディア操作、次に入力系を個別設計） | 本体＋Companion、**PC Control Lab 新規** | 未着手 |
| 5 | Network R7 | Browser/LAN診断、ブラウザUI、通信診断 | 本体API、**Browser Lab 新規**、Game Server Lab拡張 | 未着手 |
| 6 | Game R8 | セッション・ルーム同期・Ping・承認済みゲームサーバーへの通信 | Game Server Lab拡張 | 未着手 |
| 7 | Media R9 | 録画耐久・安全な復旧、Androidの制約と許可に合うバックグラウンド動作 | Recorder / Media Lab拡張 | 未着手 |
| 8 | Platform R10 | API対応状況・権限明示・開発者向け検査と互換性 | **API Test Lab 新規** | 未着手 |
| 9 | Release Gate | 全体の回帰・2台実機QA・署名/保存データ継続・公開判断 | 既存Debug Lab活用 | 毎段階で実施、Stableは別承認 |

## PC Link R4B 最初の8タスク

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

- R4A PR #95 は [Quick CI](https://github.com/mibesamiti-png/chappy-player/actions/runs/42443650137) と [Windows CI](https://github.com/mibesamiti-png/chappy-player/actions/runs/42443650188) 成功でmain統合済み。
- 2026-11-08、ユーザーから修正版Debug APKの**起動成功**報告。ただしPC Link両端末QAは未実施。
- [PC Link QR-v3](../pc-link-mutual-qr-v3.md) / [2台実機QA](../pc-link-two-device-qa-matrix.md) / [過去のNative API構想](../native-capabilities-roadmap.md)

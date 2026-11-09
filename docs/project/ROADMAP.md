# Chappy Player — 次に実装するロードマップ

更新: 2026-11-09。**R5AのWindows→Androidソース・Quick/Windows CIは完了。次はR5BのAndroid→Windows転送**。物理2台QAは0/15、未実施。

| 順番 | バッチ | 主な内容 | 本体/ミニアプリ | 現状 |
| --- | --- | --- | --- | --- |
| 1 | PC Link R4B | 期限/双方同意/権限分離、Python/Dart合同の127.0.0.1通信テスト | WindowsとDartの**テスト専用**モデル。新規Debugミニアプリなし | **ソース統合・CI成功（実PC接続なし）** |
| 2 | PC Link R4C | QR-v3署名/TLSピン＋双方別承認の1回限定PC状態取得（CPU/RAM/起動時間） | 本体ホスト画面＋Windows Companion。新規Debug Labなし | **ソース統合・CI成功、実機QA未実施** |
| 3 | PC Link R5A | Windowsで選んだ1ファイルを4MiB・16KiB分割でAndroidへ、安全な承認とSHA-256後に保存 | 本体＋Companion、PC Transfer Lab新規（非公開Debug QA） | **ソース/CI成功・実機QA未実施** |
| 3b | PC Link R5B | AndroidからPCへの本人選択ファイル送信・PC保存先選択・安全な一時ファイル処理 | 本体＋Companion、PC Transfer Lab拡張 | **次・未着手** |
| 4 | PC Link R6 | 明示的承認を伴う限定リモート操作（まず音量・メディア操作、次に入力系を個別設計） | 本体＋Companion、**PC Control Lab 新規** | 未着手 |
| 5 | Network R7 | Browser/LAN診断、ブラウザUI、通信診断 | 本体API、**Browser Lab 新規**、Game Server Lab拡張 | 未着手 |
| 6 | Game R8 | セッション・ルーム同期・Ping・承認済みゲームサーバーへの通信 | Game Server Lab拡張 | 未着手 |
| 7 | Media R9 | 録画耐久・安全な復旧、Androidの制約と許可に合うバックグラウンド動作 | Recorder / Media Lab拡張 | 未着手 |
| 8 | Platform R10 | API対応状況・権限明示・開発者向け検査と互換性 | **API Test Lab 新規** | 未着手 |
| 9 | Release Gate | 全体の回帰・2台実機QA・署名/保存データ継続・公開判断 | 既存Debug Lab活用 | 毎段階で実施、Stableは別承認 |

## 次バッチ：PC Link R5B の8タスク（未着手）

1. Android→PCの独立署名スコープpc.file.send、両側の別同意（本人確認/R5A/R4Cの権限から独立）。
2. Androidの本人選択SAFファイルだけを扱い、容量・名前・内容の境界を守る。
3. Windows側も保存先を本人が明示指定。遠隔指定したPCパスやフォルダ閲覧は拒否。
4. 転送チャンク・順序・サイズ・SHA-256・リプレイの検証。
5. 断線・拒否・キャンセル・ハッシュ不一致で一時ファイルを削除し、不完全データを公開しない。
6. PC Transfer Lab 0.1.0を双方向QAへ拡張（ミニアプリJSへ特権は直接公開しない）。
7. 不正パス・誤署名・過大ファイル・並行要求・期限切れの自動テスト。
8. Quick/Windows CI、Android Debug APK・実機QAを別判定、GitHub/Notion節目更新。

大容量・途中再開・フォルダ同期は次の拡張。現状のR5AはWindows→Android限定で4MiB上限。

## R5A完了（ソース・CI、実機未確認）

- [PR #101](https://github.com/mibesamiti-png/chappy-player/pull/101) 統合。main: ae130dfbc3e1ca2a47abe29f43447e837ecf103f。
- [Quick CI #42595700596](https://github.com/mibesamiti-png/chappy-player/actions/runs/42595700596) と [Windows CI #42595700748](https://github.com/mibesamiti-png/chappy-player/actions/runs/42595700748) はともに成功。
- PCで選択した1ファイルのみを16KiBチャンクで転送。QR-v3本人確認と別SEND/Android承認、新署名、期限/再利用拒否、SHA-256とAndroid Save As。
- Windows Preview EXEと非公開Debug PC Transfer Lab .chappyがCI成果物にある。Android→PC・再開・4MiB超は未実装。
- **Android↔Windowsで実転送成功は未確認。** 物理2台QA 0/15、公開Chappy Apps・署名Stable未更新。[R5A仕様](../pc-link-r5a-file-receive.md)。
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

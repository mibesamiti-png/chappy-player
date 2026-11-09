# Chappy Player — 次に実装するロードマップ

更新: 2026-11-10。**Network R7はソースmain統合・Quick/Android Debug CI成功。次はGame R8（未着手）**。R7実機0/12、PC Link 0/15+0/13未実施。

| 順番 | バッチ | 主な内容 | 本体/ミニアプリ | 現状 |
| --- | --- | --- | --- | --- |
| 1 | PC Link R4B | 期限/双方同意/権限分離、Python/Dart合同の127.0.0.1通信テスト | WindowsとDartの**テスト専用**モデル。新規Debugミニアプリなし | **ソース統合・CI成功（実PC接続なし）** |
| 2 | PC Link R4C | QR-v3署名/TLSピン＋双方別承認の1回限定PC状態取得（CPU/RAM/起動時間） | 本体ホスト画面＋Windows Companion。新規Debug Labなし | **ソース統合・CI成功、実機QA未実施** |
| 3 | PC Link R5A | Windowsで選んだ1ファイルを4MiB・16KiB分割でAndroidへ、安全な承認とSHA-256後に保存 | 本体＋Companion、PC Transfer Lab新規（非公開Debug QA） | **ソース/CI成功・実機QA未実施** |
| 3b | PC Link R5B | AndroidからPCへの本人選択ファイル送信・PC保存先選択・安全な一時ファイル処理 | 本体＋Companion、PC Transfer Lab拡張 | **ソース統合・Quick/Windows CI成功、実機QA未実施** |
| 4（開発段階完了） | PC Link R6 | R6A：限定メディア操作、R6B：署名/HTTP/Win32モック検証と実機QAキット | 本体＋Companion、**private PC Control Lab 0.1.0**、Debug APK 3 ABI | **R6Bソース/3 CI成功・実機QAは0/15＋0/13** |
| 5（開発段階完了） | Network R7 | 公開HTTPSホストブラウザ、1回だけ承認DNS/HTTPS診断 | Android本体、**private Browser Lab 0.1.0**、Debug APK 3 ABI | **ソース/Quick/Android CI成功、実機0/12未実施** |
| 6（次） | Game R8 | セッション・ルーム同期・Ping・承認済みゲームサーバーへの通信 | Game Server Lab拡張・private Game Room Lab候補 | 計画・未着手 |
| 7 | Media R9 | 録画耐久・安全な復旧、Androidの制約と許可に合うバックグラウンド動作 | Recorder / Media Lab拡張 | 未着手 |
| 8 | Platform R10 | API対応状況・権限明示・開発者向け検査と互換性 | **API Test Lab 新規** | 未着手 |
| 9 | Release Gate | 全体の回帰・2台実機QA・署名/保存データ継続・公開判断 | 既存Debug Lab活用 | 毎段階で実施、Stableは別承認 |

## 【次】Game R8 — ルーム同期と本人参加型通信（8タスク・未着手）

1. 既存Game Server Lab/mini-appネットワークAPIとWSSサーバー例の監査。
2. 明示的に選択した接続先への一時セッション開始/終了。
3. ルームID・最小プレイヤー識別子・参加/退室イベント設計。
4. メッセージ順序・サイズ/頻度/同時接続の上限と重複再送処理。
5. ユーザー操作のPing/遅延・タイムアウト・可視の切断。
6. private Game Room Labによる手動QA、バックグラウンド自動接続はしない。
7. オフライン・拒否・同時要求・背景化のFlutter/JS/サーバーテスト。
8. 最終HEAD Quick CI/Debug APKと実機QA/Stable公開を別管理しGitHub/Notion更新。

## 【R7完了記録】本体Browser/接続診断（ソース・CIのみ）

- [R7 PR #116](https://github.com/mibesamiti-png/chappy-player/pull/116)をmain d5865dba6955に統合。[Quick CI #42658869004](https://github.com/mibesamiti-png/chappy-player/actions/runs/42658869004)全63成功・[Android Debug #42658868997](https://github.com/mibesamiti-png/chappy-player/actions/runs/42658868997)全17成功。ARM64/ARM32/x86-64 APK・private Browser Lab `.chappy` 成果物あり。
- JSデフォルトOFF、HTTPS URL/遷移の制限、ページ権限拒否、明示的なCookie削除確認。診断は本人同意後のexample.com固定DNS+HTTPS HEADだけ。ミニアプリJSへのブラウザ/診断特権なし。
- **実機ブラウザ/診断0/12未実施**。WebView Cookie共有とサブリソース・DNS rebindingの制限が残る。PC Link 0/15+0/13、Stable公開/カタログも変更なし。[仕様](../network-r7-browser-diagnostics.md)。

---

## 【履歴：R6B時点】Network R7の計画（当時未着手）

R6A/R6Bのプレビューはソース/CIまで統合。PC Linkの物理QAはNETLAB-03B **0/15**、媒体操作 **0/13**で全て未実施のまま。新しいR7はこれらの実機PASS判定を変更しない。HTTPSとアプリ権限境界を優先し、ユーザーの明示操作に限定したブラウザ・LAN診断を作る。

1. 既存WebView・Network Lab・mini-app sandboxの安全境界を監査。
2. Android本体で明示起動するBrowser UI（URL入力、戻る/進む、更新）。
3. HTTPS制限・危険スキーム拒否・WebViewのナビゲーション/ダウンロード保護。
4. 明示実行の接続可否・DNS・LAN診断。無断スキャン/パケット監視はしない。
5. 履歴/サイトデータの最小化と利用者による削除方法を設計。
6. private Browser Lab QA・Game Server Lab連携の検討。
7. Flutter/Android/JavaScriptの異常系テスト・端末プライバシー境界検証。
8. 最終HEAD CI、Debugビルド、実機・Stable公開を分離してGitHub/Notionへ引き継ぎ。

## 【R6B完了記録】検証強化・private PC Control Lab（ソース/CI成功、実機未検証）

- [R6B PR #111](https://github.com/mibesamiti-png/chappy-player/pull/111)、main 1e7cb5e2678eへ統合。[Quick CI #42611593883](https://github.com/mibesamiti-png/chappy-player/actions/runs/42611593883)、[Windows #42611593897](https://github.com/mibesamiti-png/chappy-player/actions/runs/42611593897)、[Android Debug #42611593749](https://github.com/mibesamiti-png/chappy-player/actions/runs/42611593749) 全成功。
- Python/Dart共有署名ベクトル8件、実P-256のHTTP localhost結合と拒否・再送・競合・期限テスト、Win32モックによる固定媒体キー1 down/up、private PC Control Lab 13項目手動QAとDebug APK 3 ABI/報告書を準備。
- コードの動作実証・Android実機インストール・Windowsメディアキー操作の実機PASSは**まだない**。共通15ケース0/15、媒体13ケース0/13。Stable APK/Chappy Apps公開カタログは変更しない。[手順](../pc-link-r6b-qa.md)。

---
## 【履歴：R6A時点】PC Link R6Bの当初8タスク（現在はソース/CI完了）

R6Aは[PR #107](https://github.com/mibesamiti-png/chappy-player/pull/107)でmain統合済み。 [Quick CI #42603449636](https://github.com/mibesamiti-png/chappy-player/actions/runs/42603449636) と [Windows CI #42603450028](https://github.com/mibesamiti-png/chappy-player/actions/runs/42603450028) はPR最終HEADで成功。ただしWindows/Android物理2台でのメディア操作・Debug APK起動は**未検証 0/15**。私有PC Control Lab/フルAndroid Debug実機受入は未完了。

1. Python/Dartの`pc.media.control`ハッシュ・P-256署名の共有検証ベクトル作成。
2. localhostの隔離HTTPでQR-v3→PC CONTROL→Android独立署名→1操作を模擬実行する回帰。
3. Android UIで4操作の1回限り制御・誤タップ/重複防止のテスト。
4. 期限、拒否、バックグラウンド、ネットワーク切断/応答ロスト時の安全な終了・再利用拒否。
5. Windowsの固定マルチメディアキー実行器の単回発行とエラー/非対応環境の扱いを検証。
6. **非公開PC Control Lab** をJS権限ゼロのQAチェックリストとして追加。
7. Android Debug APKのフルビルドを別途確認し、15件の既存2台QAとR6A媒体キー実機QAの記録を分ける。
8. 最終HEAD Quick/Windows CIを通し、GitHub/Notionを更新。Stable署名配布/公開カタログは別承認。

## 【R6A完了記録】1回限りのPCメディア操作（ソース/CI完了・実機未検証）

- [PR #107](https://github.com/mibesamiti-png/chappy-player/pull/107)をmain d87b00e661ce に統合。Windows `Start-ChappyMediaOnceV3.cmd`/`--media-once`、Android本体Network Labに4操作ボタンと別承認を追加。新しい `media=1` QR-v3・操作に結び付く独立署名。
- 期限90秒以内、同じQRにつき1回。Windows本人のCONTROLとAndroid前景同意を確認。任意キーボード/マウス・シェル・ファイル操作や自動再接続は不可。
- CIはMock実行器による署名・拒否/リプレイ検査とFlutter解析/ユニット、Windows EXE/CMD成果物。実機で音量が変わったとはまだ宣言しない。[仕様](../pc-link-r6a-media-once.md)。

---
## 【履歴：R5B時点のR6計画】独立承認の限定メディア操作（当時未着手）

R5A/R5Bのファイル権限やR4Cの状態取得権限とは分離した新しい一回限りの承認を追加する。最初の対象は音量・ミュート・再生/一時停止の最小ホワイトリストに限定。PCの任意コマンド、キーボード/マウス全般、永続制御、バックグラウンド接続は含めない。

1. `pc.media.control` の独立した署名/権限、期限と再利用拒否の設計。
2. Windows Companionを本人が明示起動し、別途操作許可を確認。
3. Android側でも操作前の独立同意・キャンセル・短命許可を設計。
4. 操作ホワイトリストと値の境界、デフォルト拒否を実装。
5. QR-v3 P-256/TLSピンとスコープの整合、不正入力/リプレイ検査。
6. 期限、切断、背景化時に権限破棄。診断は秘密を記録しない。
7. Dart/Pythonの隔離テストとミニアプリJSへの特権不公開を検証。
8. Quick CI/Windows CI、Debug APK、15項目の物理2台QAを区別して進捗記録。

## 【R5B完了記録】Android→Windowsファイル転送（ソース/CI成功・実機未検証）

- [PR #103](https://github.com/mibesamiti-png/chappy-player/pull/103) main統合 `1ed1f7d21861`。PR最終HEAD `b1e3e81603f8`。
- [Quick CI #42599611400](https://github.com/mibesamiti-png/chappy-player/actions/runs/42599611400) / [Windows CI #42599611377](https://github.com/mibesamiti-png/chappy-player/actions/runs/42599611377) ともに成功。Private PC Transfer Lab 0.2.0の成果物とWindows Preview EXEあり。
- Android本人選択の単一ファイル（上限4MiB）→PC本人が起動前に選んだ新規保存先。QR-v3相互認証、別Windows RECEIVE/Android確認、`pc.file.upload` P-256署名、16KiB順序/サイズ、SHA-256、一時ファイル隔離＋上書き拒否。実機QA 0/15は未実施、公開カタログ・署名Stableは不変。[詳説](../pc-link-r5b-upload-once.md)。

### R5B実装時の8つのチェック観点（履歴）

1. Android→PCの独立署名スコープpc.file.send、両側の別同意（本人確認/R5A/R4Cの権限から独立）。
2. Androidの本人選択SAFファイルだけを扱い、容量・名前・内容の境界を守る。
3. Windows側も保存先を本人が明示指定。遠隔指定したPCパスやフォルダ閲覧は拒否。
4. 転送チャンク・順序・サイズ・SHA-256・リプレイの検証。
5. 断線・拒否・キャンセル・ハッシュ不一致で一時ファイルを削除し、不完全データを公開しない。
6. PC Transfer Lab 0.1.0を双方向QAへ拡張（ミニアプリJSへ特権は直接公開しない）。
7. 不正パス・誤署名・過大ファイル・並行要求・期限切れの自動テスト。
8. Quick/Windows CI、Android Debug APK・実機QAを別判定、GitHub/Notion節目更新。

大容量・途中再開・フォルダ同期は次の拡張。R5AがPC→Android、R5BがAndroid→PC。どちらも1ファイル4MiB上限、ソース/CI完了・実機未確認。

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

# Chappy Player — 単一チャット高速開発 v2 最新引き継ぎ

更新: 2026-11-09。R5B統合時点のmainスナップショット: 1ed1f7d2186148e4ba8fd2dcedb2cf909767ef1b。再開時は必ずGitHub最新main HEAD・Open PR・Actionsを再取得。

## 【最新】R5B統合済み・R6が次｜2026-11-09

- **R5AはPR #101でmain統合済み**。PC→Android 1ファイル・4MiB/16KiB・別のSEND/Android承認・SHA-256/Save As。PR #102でR5AのSTATE/HANDOFF/ROADMAPを更新済み。
- **R5Bも[PR #103](https://github.com/mibesamiti-png/chappy-player/pull/103)でmain統合済み**。統合SHA 1ed1f7d2186148e4ba8fd2dcedb2cf909767ef1b、最終PR HEAD b1e3e81603f8a14843bffc0507d4430cab421ef9。Android→Windowsを1ファイル4MiB限定で送信し、保存先はPC本人が起動前に絶対パスで指定。Windows RECEIVE + Android別承認、独立した `pc.file.upload` 署名、順序付き16KiB、SHA-256、一時ファイルと上書き防止処理。R5A/R4Cの権限流用不可。
- [R5B Quick CI #42599611400](https://github.com/mibesamiti-png/chappy-player/actions/runs/42599611400) **成功**（test-build、R5B境界・Flutter解析/Unit test・非公開PC Transfer Lab 0.2.0成果物）。[Windows Companion Preview CI #42599611377](https://github.com/mibesamiti-png/chappy-player/actions/runs/42599611377) **成功**（P-256/上書き防止・実Windowsテスト・EXEプレビュー）。どちらもPR #103の最終HEADに対する確認。
- **実際のAndroid↔Windows物理QAは0/15・未実施**。R5A/R5Bの新Debug APKを端末で動作確認した証拠なし。Stable APK v0.3.0-b11、公開Chappy Apps Debug 8 / Stable 2は変更なし。
- **次はR6（予定・未着手）**：限定的PCメディア操作（音量/ミュート/再生・一時停止）だけを新しい個別承認と署名スコープで設計/実装。任意コマンド・キーボード/マウス入力・自動再接続・無断ファイルアクセスは依然禁止。R5Bの4MiB超・途中再開/複数転送も未実装。
- R5B詳細：[仕様](../pc-link-r5b-upload-once.md)。引き継ぎ正本：[STATE](STATE.json) / [ROADMAP](ROADMAP.md) / [SINGLE_CHAT_DEVELOPMENT](SINGLE_CHAT_DEVELOPMENT.md)。この下のR5A「R5B未着手」は2026-11-09の過去チェックポイントであり現在地ではない。

---

## 【履歴】R5A時点の確定結果

- **R5A Windows→Android 1ファイル転送のソース統合済み**。[PR #101](https://github.com/mibesamiti-png/chappy-player/pull/101)、統合main ae130dfbc3e1ca2a47abe29f43447e837ecf103f。
- [Quick CI #42595700596](https://github.com/mibesamiti-png/chappy-player/actions/runs/42595700596) **成功**。Flutter analyze/test、安全性チェックとPC Transfer Lab .chappyパッケージ生成。
- [Windows CI #42595700748](https://github.com/mibesamiti-png/chappy-player/actions/runs/42595700748) **成功**。QR-v3署名・SEND別承認・ファイル境界/リプレイ検査・Windows EXE生成。
- PC Transfer Lab 0.1.0 は private source / GitHub Actions Debug成果物。まだChappy Apps公開Debugカタログには載せていない。ミニアプリ自身にPC接続/ファイルアクセス権なし。
- **Windows↔Android実機QAは未実施（PC Link 0/15）。** 以前のAndroid Debugの起動確認はR5A転送の成功ではない。新しいR5A Android APKを実機で確認した証拠もない。
- 署名済みStable APK v0.3.0-b11と公開Chappy Apps Debug 8 / Stable 2 は変更していない。

## 安全なR5Aプレビューの境界

- Windows側はStart-ChappyFileOnceV3.cmdで1ファイルをローカル選択。PC上のフォルダ一覧や任意ファイルパスをスマホに提供しない。
- 本物のQR-v3本人確認（PC YES、Android署名）後に、別のWindows SENDとAndroid受信確認が必要。スコープはpc.file.receiveでありpc.status.readとは別。
- 最大4MiB、16KiBの順序付き分割、期限240秒以下、リプレイ/改ざん拒否、SHA-256検証後にAndroidのOS標準Save As。
- 未実装: Android→PC逆方向、大容量/途中再開/フォルダ同期、PCリモート操作、永続認可、自動再接続。新しい転送権限をミニアプリJSへ開かない。

## 【履歴】R5A完了時点の次タスク：PC Link R5B（現在は統合済み）

Androidでユーザーが選んだファイルをWindowsのユーザーが指定した保存先へ一度だけ送り、チャンク、ハッシュ、期限、キャンセルと一時ファイルの確実な削除を実装。PC Transfer Labの手動QAも双方向へ拡張。

初読の順番: [STATE.json](STATE.json) → [ROADMAP.md](ROADMAP.md) → [SINGLE_CHAT_DEVELOPMENT.md](SINGLE_CHAT_DEVELOPMENT.md) → [R5A仕様](../pc-link-r5a-file-receive.md) → [PC Link 2台QA](../pc-link-two-device-qa-matrix.md)。
対象: examples/windows_companion/file_send_once.py, pairing_server.py, companion.py; lib/core/pc_file_receive.dart, companion_identity_exchange.dart, lib/screens/companion_pairing_page.dart; tools/test_pc_file_once.py, test/pc_file_receive_test.dart。

**R4B/R4Cは過去の完了履歴。** GitHubが正本、Notionは節目の手動更新であり常時自動同期は未実装。

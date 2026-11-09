# Chappy Player — 単一チャット高速開発 v2 最新引き継ぎ

更新: 2026-11-10。Network R7統合mainスナップショット d5865dba695572af5cdd036799fc31a732f8da36。作業開始時に必ず最新main HEAD/PR/CIを再取得。

## 【最新】Network R7ソース/CI完了 → 次はGame R8｜2026-11-10

- [R7実装PR #116](https://github.com/mibesamiti-png/chappy-player/pull/116)はmain d5865dba695572af5cdd036799fc31a732f8da36へ統合済み。本人が明示起動するAndroid本体Browserと1回限定のDNS/HTTPS接続診断を追加。JavaScript初期OFF・確認後のみON、ページ権限拒否、入力/遷移時の公開HTTPSドメイン制限、戻る/進む/更新・手動閲覧データ削除。private Browser Lab 0.1.0は権限`[]`、手動QA12項目のみ。
- **R7の最終main CI成功**：[Quick #42658869004](https://github.com/mibesamiti-png/chappy-player/actions/runs/42658869004) 全63ステップ、[Android Debug #42658868997](https://github.com/mibesamiti-png/chappy-player/actions/runs/42658868997) 全17ステップ。Debug APK ARM64/ARM32/x86-64とprivate Browser Lab .chappyが生成された。Windows側変更なしのため専用Windows CIをR7合格根拠とはしていない。
- **実機QAは全て未実施**：R7 Browser/診断 0/12、PC Link共通 0/15、媒体キー 0/13。APKは生成されただけで、Androidへのインストール・WebView実閲覧・DNS実通信の物理PASSは未確認。公開カタログ・署名Stable APKは変更なし。
- **WebViewの既知制約**：URL検査はDNS rebindingや全サブリソースのアクセス遮断を保証しない。Android WebViewのCookieやキャッシュは他のmini-appと共有される場合があり、削除は広範なログアウトを招く。フル機能の安全ブラウザではなくDebugプレビューとして扱う。
- **次はGame R8（未着手・8タスク）**：既存Game Server Labの明示的接続・同意を保ち、ルーム参加/退室、同期状態、Ping・タイムアウト・切断を実装する。無断サーバー接続、バックグラウンド常駐・PC遠隔操作などの権限拡大は禁止。R7の実機QAは別途保持。
- 正本：[STATE](STATE.json) / [ROADMAP](ROADMAP.md) / [R7仕様](../network-r7-browser-diagnostics.md)。Notionは手動ミラーで、開始時は最新main/PR/CIを再取得する。

---

## 【履歴：R6B時点】R6Bソース/3系統CI成功 → 当時の次Network R7｜2026-11-09

- [R6B PR #111](https://github.com/mibesamiti-png/chappy-player/pull/111)をmainに統合（コミット 1e7cb5e2678ea3b03be5a23b34723dc1fc66c825）。R6Aの固定4種メディア操作の認証・隔離HTTP・同時再送拒否・Win32固定キーの模擬発行・UI拒否/切断手順を強化。Python/Dartの共有SHA-256署名ベクトル8つを検証。
- **3系統の最終PR HEAD CI成功**：[Quick #42611593883](https://github.com/mibesamiti-png/chappy-player/actions/runs/42611593883) Flutter解析/Unit＋private PC Control Lab 0.1.0生成、[Windows #42611593897](https://github.com/mibesamiti-png/chappy-player/actions/runs/42611593897) 実P-256鍵でlocalhost HTTPと模擬Win32固定キー検証/Windows EXE、[Debug APK #42611593749](https://github.com/mibesamiti-png/chappy-player/actions/runs/42611593749) ARM64/ARM32/x86-64ビルド＋互換性レポート/成果物。
- **private PC Control Lab**：`local.chappy.pc_control_lab` v0.1.0、`permissions: []`。メディアキーを実行する機能はなく、13項目の手動QA観察・匿名化レポート生成のみ。旧PC Transfer LabやASMRなど別開発も保持し、Stable署名APK/公開カタログは変更しない。
- **実機QAは未実施**：NETLAB-03B共通15件は **0/15**、R6B媒体キー13件は **0/13**。Android Debugビルド生成はインストール/Windows↔Android相互接続の確認ではない。実機メディア操作やWi-Fi/TLSは別途本人の実機テストを要する。
- **次はNetwork R7（予定・未着手）**：Androidホストのユーザー起動ブラウザ＋LAN診断・private Browser Labを8タスクで進める。ネットワーク監視・任意PC操作・ミニアプリJS特権は拡張しない。R6Bの未実機QAも別ゲートで維持。
- 正本：[STATE](STATE.json) / [ROADMAP](ROADMAP.md) / [R6B QA](../pc-link-r6b-qa.md) / [R6Bベクトル](../pc-link-r6b-media-vectors.json)。Notionは節目の手動ミラーであり常時自動同期ではない。

---
## 【履歴：R6A時点】R6Aソース/CI完了 → 当時の次バッチR6B｜2026-11-09

- **PC Link R6A**: [PR #107](https://github.com/mibesamiti-png/chappy-player/pull/107) をmainへ統合。基準コミット d87b00e661ce9ea83e17af37ad5898b0c155654c。QR-v3 `media=1`、Windows明示 `--media-once`/専用CMD、音量上下・ミュート切替・再生/一時停止の固定4キーを追加。
- QR-v3のPC YES/Android相互署名を保持し、**別のWindows CONTROL（操作を画面表示）＋Android前景別承認**を要求。`pc.media.control` にコマンド名を含むP-256新署名、期限90秒以内、QRにつき1回だけ実行。PC状態/ファイル権限を流用しない。ミニアプリJS、任意PCコマンド、一般キーボード/マウス、継続接続には一切公開しない。
- **CI最終HEAD合格**: [Quick CI #42603449636](https://github.com/mibesamiti-png/chappy-player/actions/runs/42603449636) Flutter analyze/test・権限隔離。 [Windows CI #42603450028](https://github.com/mibesamiti-png/chappy-player/actions/runs/42603450028) 署名/拒否/再実行防止のPythonモック検証・EXE/専用CMDアーティファクト生成。
- **PC Link物理2台QAは0/15、未実施**。Windows実キー操作やR6A Android Debug APKの起動/転送などは物理的に未確認。EXE生成とCIは実機動作を保証しない。Stable署名APK v0.3.0-b11、公開Chappy Apps Debug 8/Stable 2は変更していない。
- **次はR6B（予定・未着手）**: Python/Dart共有署名ベクトル、隔離したHTTP結合試験、前景拒否・中断・応答ロスト回帰、private PC Control Lab (QAのみ・JS無権限)、フルDebug APKと15件QAを別追跡。任意のPC遠隔入力・継続的権限は含めない。
- 最新仕様: [R6A](../pc-link-r6a-media-once.md) / [STATE](STATE.json) / [ROADMAP](ROADMAP.md)。この下の「R6未着手」はR5B時点の過去記録。GitHub main/PR/CIが正本、Notionは節目に手動更新。

---
## 【履歴：R5B時点】R5B統合済み・当時の次バッチR6｜2026-11-09

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

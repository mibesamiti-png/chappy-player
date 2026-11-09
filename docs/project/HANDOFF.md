# Chappy Player — 単一チャット高速開発 v2 最新引き継ぎ

更新: 2026-11-10。NETLAB-05C（ルーターのIP・UPnP型番候補の自動識別）実装ソースmainスナップショット 53aa672000364c31cab4986524f649e33fdfb3e1。BUFFALOの実機型番/ファームウェアは未確認。再開時は必ず最新main・PR・CIを再取得。

## 【最新】NETLAB-05C ルーター自動識別（Wi-Fi Gateway + UPnP公開モデル候補）ソース/CI統合済み・実機未検証｜2026-11-10

- ユーザーはルーターメーカーを**BUFFALO**と申告。ただし型番が分からないため**型番なしで自動識別する機能**を追加。[実装PR #127](https://github.com/mibesamiti-png/chappy-player/pull/127) をmain `53aa672000364c31cab4986524f649e33fdfb3e1`へ統合済み。**最終実装HEAD `ac064f571e93a9592f12e2519a4c7e3e67ab6599`の[Quick CI #42697064380](https://github.com/mibesamiti-png/chappy-player/actions/runs/42697064380) 67/67と[Android Debug #42697064416](https://github.com/mibesamiti-png/chappy-player/actions/runs/42697064416) 17/17成功、ARM64/ARM32/x86-64 APK＋互換性レポート生成。**
- **UI**：Android本体Network Lab→「接続中のルーターを自動識別（型番候補）」。管理するWi-Fiの本人承認 + **毎回の確認ダイアログ**で1回だけ実行。Android OSの現在のWi-FiデフォルトゲートウェイRFC1918 IPv4を読み出す（VPN/セルラー拒否）。
- **UPnPモデル候補**：限定SSDP `M-SEARCH upnp:rootdevice` 1送信、最大2.4秒/8応答/各2KiBで**ゲートウェイ送信元の応答だけ**を受理。同じゲートウェイIPのLOCATIONに限り公開説明XMLを認証なしHTTP GET 1回（16KiB、リダイレクト/Proxy禁止、タイムアウト1.2秒）。メーカー/モデル名/型番/機器名は**UPnP自己申告なので候補にすぎない**。UPnP不可でも**ゲートウェイIPのみ「型番不明」**として表示する。BUFFALOがAP/ブリッジなら上流機器を指しうる。
- **安全境界**：資格情報/管理画面の自動ログイン/設定変更/他端末の一覧や通信先/URL/本文取得は一切しない。結果はRAMのみで背景化/画面終了/削除で破棄。Android本体専用、.chappy JSへ特権なし、広範な新Androidローカルネットワーク権限も追加なし。
- **物理QAは未実施**：Debug APKの実端末インストール、実BUFFALOのUPnP応答・経路/型番照合は未確認。ユーザーが新画面を実機で使って返ったIP/UPnPモデル候補を公式AirStationアプリ/本体ラベルなどで照合し、**機種特定後にのみBUFFALOの公式読取API・端末一覧自動取得可能性**を検証する。既存NETLAB-05Bの未登録/非ペアリング端末一覧は引き続き**手動コピー方式**。他端末の通信先IPは今回未実装。
- [仕様/限界](../netlab-05c-router-auto-identification.md) / [STATE](STATE.json) / [ROADMAP](ROADMAP.md)。Game R8の8タスク、NETLAB-04A/04B、OpenWrt 05A、ASMR、Stable/公開カタログは保持。

---

## 【履歴：05Cより前】NETLAB-05B BUFFALOルーター端末一覧、未登録機器もオフライン読込｜ソース/2CI統合・自動APIは型番待ち｜2026-11-10

- ユーザー確認：ルーターメーカーは**BUFFALO**。「まだ登録・許可していない端末も読み込みたい」。**型番とファームウェアは未確認**なので、一般BUFFALOの自動APIや通信先IP取得は未実装と明示。
- [実装PR #125](https://github.com/mibesamiti-png/chappy-player/pull/125)をmain `57e67f6252ebd105fa5712a1332f0db8f4636de7`へ統合。実装最終HEAD `aa915e339e150bfd6e03e497f3bd747058e0fa85` で [Quick #42691745989](https://github.com/mibesamiti-png/chappy-player/actions/runs/42691745989) **66/66**、[Android Debug #42691746433](https://github.com/mibesamiti-png/chappy-player/actions/runs/42691746433) **17/17**成功。3ABI Debug APK ARM64/ARM32/x86-64、互換性レポートあり。Windows変更なし。
- **実装内容**：Android本体Network Lab→BUFFALOの接続端末一覧。自分が管理するBUFFALO設定画面（デバイスコントロール/クライアントモニター）から**ユーザーがIP/MAC/端末名の行を自分でコピーして貼り付ける**。ほかの端末のChappyインストールやペアリング不要。すべての有効行を一覧に出し、端末をRAMだけで「未登録・要確認」「既知」に分類。未登録≠無断侵入。上限32KiB/256行/128台、重複と外部IPを除去、背景化/終了/手動消去で破棄。admin資格情報・自動LANスキャン・mini-app JS特権・通信先情報の追跡をしない。
- **実機QAは未実施**：BUFFALOの実際の管理画面からコピーした一覧をAndroidで解析・実機APKインストールは未確認。ルーターへ**自動接続する仕組みはまだない**。接続端末一覧だけから、その端末がどのWebサイトやIPへ通信中かは分からない。
- **次のNETLAB-05B**：ユーザーの型番とファームウェアを取得し、管理UI/APIで機器一覧と接続先情報のうち何を自動取得できるか監査・実機QA。先行OpenWrt NETLAB-05AとPC Link 04A/04B/ASMRは維持し、Game R8の8タスクもSTATE内で延期保持。Stable/公開カタログ未更新。
- [BUFFALO仕様](../netlab-05b-buffalo-inventory.md) / [BUFFALO公式接続機器手順](https://www.buffalo.jp/support/faq/detail/15741.html) / [STATE](STATE.json) / [ROADMAP](ROADMAP.md)。Notionは手動ミラー。正本はGitHub main/CI。

---

## 【履歴：05B手動版より前】NETLAB-05A管理ルーター接続先情報：OpenWrt版ソース/2CI統合 → 次は機種別対応 NETLAB-05B｜2026-11-10

- **[PR #123](https://github.com/mibesamiti-png/chappy-player/pull/123) をmain `ffdeebd7fda5c867db56917e711a37b655d84951`に統合。** 最終実装HEAD `b0de4215c1541cd831bfbbdc32a56b969ed4bf78` で [Quick #42685427286](https://github.com/mibesamiti-png/chappy-player/actions/runs/42685427286) **65/65**、[Android Debug #42685427387](https://github.com/mibesamiti-png/chappy-player/actions/runs/42685427387) **17/17**成功。ARM64/ARM32/x86-64 APKと互換性レポートあり。Windowsコード変更なし。
- **本体Network LabにRouter Connection Labを追加**。現時点の対応は**OpenWrt LuCI HTTPS /ubusのみ**。本人管理ルーターのプライベートIPv4・HTTPSポート・独立確認済み証明書指紋SHA-256・LuCI管理資格情報と、情報取得を許可された対象端末のプライベートIPv4を自分で入力。前景Wi-Fi・VPNなし・新しい明示同意を要求。
- **読取専用契約**：`session.login` / `luci-rpc.getDHCPLeases` / `luci.getConntrackList` だけ。対象端末を元方向`src`で厳密一致、現在の接続先IP・ポート・TCP/UDP等を上限付きでRAM表示。セッション・パスワード・端末IP等は終了/背景化で消去。IPから実際の閲覧サイトやアプリ名を断定しない。パケット本文の盗聴や任意ルーター操作、mini-app JS権限追加なし。
- **物理実機QAは未実施**。ユーザーのルーター機種/ファームウェアが未提示なので、OpenWrt以外が使えるとは宣言しない。Android Debug APK生成を実機接続成功と扱わない。旧NETLAB-04A/04B、PC Link実機0/15＋媒体0/13、R7実機0/12も別ゲート維持。署名Stable/公開Chappy Appsカタログ変更なし。
- **次はNETLAB-05B**：実際のルーターメーカー・型番確認後の機種別API対応と許可済み端末の選択UI・実機QA。Game R8の元8タスクはSTATE.observations.deferredGameR8およびROADMAPに残し、ルーター対応後に再開する。
- 正本：[NETLAB-05仕様](../netlab-05-router-connection-lab.md) / [STATE](STATE.json) / [ROADMAP](ROADMAP.md)。Notionは手動の確認済みミラー。

---

## 【履歴：05A実装前】NETLAB-04B Wi-Fi経由の本人PC通信量取得、ソース/3CI統合完了 → 次はGame R8｜2026-11-10

- **[実装PR #121](https://github.com/mibesamiti-png/chappy-player/pull/121)をmain `664802dba4b899d0334ef4ba845c96fdfe0a9861` に統合。** 正本 `STATE.json` の NETLAB-04B-01〜08 の8タスクは、コード/CI/記録ゲートまで完了。前バッチNETLAB-04Aの手動JSON読込とASMRを含む既存機能は維持。
- **最終PR HEAD `7aff08d5cfbd3145f78f43ce6546b44e92b9ff97` で3 CI全成功**：[Quick #42676947378](https://github.com/mibesamiti-png/chappy-player/actions/runs/42676947378) 64/64、[Windows #42676947845](https://github.com/mibesamiti-png/chappy-player/actions/runs/42676947845) 28/28、[Android Debug #42676947259](https://github.com/mibesamiti-png/chappy-player/actions/runs/42676947259) 17/17。Windows EXE＋`Start-ChappyTrafficReadOnceV3.cmd`、Android ARM64/ARM32/x86-64のDebug APK成果物あり。
- **機能**：本人がWindows Companionを明示起動、QR-v3 `traffic=1`・双方P-256署名・TLSピン。まずPC YESとAndroid相互認証、通信量取得には **Windows TRAFFIC別承認＋Android前景の別承認** を追加。5〜30秒・1秒ごとの全NIC合計RX/TXカウンターのみを1回だけ暗号化経路で受信し、Android本体RAMに合計/平均/ピーク/推移を表示・消去。端末名、IP、SSID、接続先、本文、他機器は返さない。mDNSや履歴だけでは許可しない。VPN/非Wi-Fi経路、リプレイ、キャンセルや失効を拒否。
- **実機QAと公開は別判定**：物理Windows↔AndroidでのWi-Fi QR/TLS接続・TRAFFIC承認・カウンター計測/受信は **未実施**。PC Link共通0/15、媒体キー0/13、R7 0/12は変更なし。Android Debug APKの実機インストールも未確認。署名Stable（既存 `v0.3.0-b11`）と公開Chappy Appsカタログは変更せず。
- **次に実装するGame R8（8タスク未着手）**：本人が選んだゲームサーバーへの一時参加、ルーム/参加・退出/同期、メッセージのレート・容量/再送制限、ユーザー主導Pingと切断、private Game Room LabのQA。無断サーバー接続、常駐、PCコマンド実行、mini-appへの権限逸脱は不可。
- 参照：[04B仕様](../netlab-04b-consented-traffic-once.md) / [STATE](STATE.json) / [ROADMAP](ROADMAP.md) / [04A旧方式](../netlab-04a-remote-traffic-report.md)。GitHub main/PR/CIが正本。Notionは手動ミラー。

---

## 【履歴：04B実装前】NETLAB-04A PC通信量レポート読込完了 → 当時の次はNETLAB-04B｜2026-11-10

- **[NETLAB-04A PR #119](https://github.com/mibesamiti-png/chappy-player/pull/119)をmain 38c35433ab793b2dfff9bf4726d66fbd4cc3b2f9に統合。** 管理Windows PC側でTRAFFIC同意→5〜30秒の全NIC送受信カウンター（Wi-Fi専用ではない）を上書き禁止JSONへ保存。Android本体Network LabでOSファイル選択→16KiB/厳格スキーマ検証→合計/平均/ピーク/1秒推移をRAMに表示、背景化・終了時消去。**ファイル経由でありWi-Fiでの直接読込や他機器パケット捕捉はまだない。**
- **最終PR HEADで3 CI全成功**：[Quick #42668253644](https://github.com/mibesamiti-png/chappy-player/actions/runs/42668253644)64ステップ、[Windows #42668253778](https://github.com/mibesamiti-png/chappy-player/actions/runs/42668253778)28ステップ（EXE＋`Start-ChappyTrafficExport.cmd`）、[Android Debug #42668253834](https://github.com/mibesamiti-png/chappy-player/actions/runs/42668253834)17ステップ、ARM64/ARM32/x86-64 APK生成。
- **実機PC→Android手動レポート読込QA未実施**。JSON未署名、PC計測機能もOS実機で確認していない。R7ブラウザ実機0/12、PC Link共通0/15＋媒体0/13も引き続き未実施。署名Stable/公開Chappy Appsカタログは変更なし。
- **次の優先NETLAB-04B（8タスク・未着手）**：管理者本人が許可したPCとのQR-v3署名/TLS pin/双方の独立同意で、PC自身の通信集計を1回限定でWi-Fiから直接取得する。一般LANの無断スキャン・平文無認証接続・他機器のパケット本文取得はしない。Game R8は中止ではなく次の段階に繰り下げ。
- 新仕様：[NETLAB-04A](../netlab-04a-remote-traffic-report.md) / [Issue #118](https://github.com/mibesamiti-png/chappy-player/issues/118) / [STATE](STATE.json) / [ROADMAP](ROADMAP.md)。Notionは手動ミラー。

---

## 【履歴：R7時点】Network R7ソース/CI完了 → 当時の次Game R8｜2026-11-10

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

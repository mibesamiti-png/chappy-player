# Chappy Player — 次に実装するロードマップ

更新: 2026-11-10。**NETLAB-06A（許可を得たPCAPの宛先IP/port・DNS名・TLS SNI候補・平文HTTP内容解析）ソースmain統合。Quick CI 68/68・Android Debug 17/17・3ABI Debug APK成功。あくまでオフライン手動取込であり、BUFFALOから他端末の通信先/暗号化本文をライブ自動取得するものではない。実機未検証。次NETLAB-06Bで本人PC/端末側の許可付きライブメタデータと機種別公式APIを検証。** 05B残件とGame R8の8タスクを保持、Stable未更新。

| 順番 | バッチ | 主な内容 | 本体/ミニアプリ | 現状 |
| --- | --- | --- | --- | --- |
| 1 | PC Link R4B | 期限/双方同意/権限分離、Python/Dart合同の127.0.0.1通信テスト | WindowsとDartの**テスト専用**モデル。新規Debugミニアプリなし | **ソース統合・CI成功（実PC接続なし）** |
| 2 | PC Link R4C | QR-v3署名/TLSピン＋双方別承認の1回限定PC状態取得（CPU/RAM/起動時間） | 本体ホスト画面＋Windows Companion。新規Debug Labなし | **ソース統合・CI成功、実機QA未実施** |
| 3 | PC Link R5A | Windowsで選んだ1ファイルを4MiB・16KiB分割でAndroidへ、安全な承認とSHA-256後に保存 | 本体＋Companion、PC Transfer Lab新規（非公開Debug QA） | **ソース/CI成功・実機QA未実施** |
| 3b | PC Link R5B | AndroidからPCへの本人選択ファイル送信・PC保存先選択・安全な一時ファイル処理 | 本体＋Companion、PC Transfer Lab拡張 | **ソース統合・Quick/Windows CI成功、実機QA未実施** |
| 4（開発段階完了） | PC Link R6 | R6A：限定メディア操作、R6B：署名/HTTP/Win32モック検証と実機QAキット | 本体＋Companion、**private PC Control Lab 0.1.0**、Debug APK 3 ABI | **R6Bソース/3 CI成功・実機QAは0/15＋0/13** |
| 5（開発段階完了） | Network R7 | 公開HTTPSホストブラウザ、1回だけ承認DNS/HTTPS診断 | Android本体、**private Browser Lab 0.1.0**、Debug APK 3 ABI | **ソース/Quick/Android CI成功、実機0/12未実施** |
| 5a（開発段階完了） | NETLAB-04A | 管理Windows PCの全NIC交通量JSONを自分でスマホへ移して読込・可視化 | Windows Companion＋Androidホスト | **ソース/Quick/Windows/Android CI成功・実機未実施、Wi-Fiライブではない** |
| 5b（開発段階完了） | NETLAB-04B | QR-v3双方向承認で管理PCの通信集計をWi-Fiから1回限定取得 | Windows Companion＋Androidホスト | **ソース/3 CI成功、物理実機未検証** |
| 5c（開発段階完了） | NETLAB-05A | OpenWrtルーターのLuCI HTTPSから承認済み対象端末の接続先IP/ポート/通信方式を1回読み取る | Android本体Router Connection Lab | **ソース/Quick/Android Debug CI成功、実ルーター実機QAは未実施** |
| 5d（分割実装進行中） | NETLAB-05B | BUFFALOの管理画面から本人がコピーしたIP/MAC端末一覧を未登録端末も含め取込。次は機種別安全なAPIと接続先情報・実機QA | Android本体BUFFALO端末一覧 | **手動読込ソース/Quick66/Android17成功。型番未判明・自動ルーター読込と実機は未対応** |
| 5e（開発段階完了） | NETLAB-05C | 端末側でWi-FiのデフォルトゲートウェイIPを取得し、UPnPから任意のメーカー/型番候補を受け取る（見つからなければIPのみ） | Android本体Router Auto Identify | **ソース/Quick67/Android Debug17成功、実機BUFFALO未検証、型番は自己申告の候補** |
| 5f（開発段階完了） | NETLAB-06A | 許可済みPCAPファイルを手動読み取り、IPv4宛先/port・DNS問い合わせ・TLS SNI候補・平文HTTP method/path/Hostおよび本文冒頭（初期OFF）を表示 | Android本体Traffic Inspection Lab | **ソース/Quick68/Android Debug17成功、3ABI APK。PCAPNG/IPv6/HTTPS本文復号/ライブ監視は非対応、実機QAなし** |
| 5g（次） | NETLAB-06B | BUFFALOモデル/公式APIの現物確認と、本人PC・本人許可済み端末の通信先メタデータ単発ライブ表示の設計/検証 | Android host / Windows Companion（必要時） | **未着手。モデルと実機QAが必要。無断パケット傍受・MITMしない** |
| 6（その後） | Game R8 | セッション・ルーム同期・Ping・承認済みゲームサーバーへの通信 | Game Server Lab拡張・private Game Room Lab候補 | 計画・未着手（延期、廃止しない） |
| 7 | Media R9 | 録画耐久・安全な復旧、Androidの制約と許可に合うバックグラウンド動作 | Recorder / Media Lab拡張 | 未着手 |
| 8 | Platform R10 | API対応状況・権限明示・開発者向け検査と互換性 | **API Test Lab 新規** | 未着手 |
| 9 | Release Gate | 全体の回帰・2台実機QA・署名/保存データ継続・公開判断 | 既存Debug Lab活用 | 毎段階で実施、Stableは別承認 |

## 【最新】NETLAB-06A — 許可済みPCAPから通信先・DNS/TLS/平文HTTPをオフラインで解析

- [実装PR #129](https://github.com/mibesamiti-png/chappy-player/pull/129) をmain `3efe4caa0536c5dedec5a51dd7add364efd93b5e`へ統合済み。最終実装HEAD `f5c2ce5a04bcacd6e96319f355311d07605d31ef`の[Quick #42702059765](https://github.com/mibesamiti-png/chappy-player/actions/runs/42702059765) **68/68**と[Android Debug #42702059838](https://github.com/mibesamiti-png/chappy-player/actions/runs/42702059838) **17/17**成功、ARM64/ARM32/x86-64 APK成果物あり。
- **Android本体Network Lab →「通信先・平文内容をPCAPから解析（本人許可）」**で、明示同意を得た本人/対象端末許諾済みclassic PCAPをファイルピッカーから手動読込。2MiB/2500パケット/最大160表示、Raw IPv4とEthernetを解析。送信元/宛先IP:ポート・TCP/UDP・DNS問い合わせ名・TLS SNI候補・HTTPのメソッド/クエリを除いたパス/Host、初期OFFの本人明示ONで平文HTTP text/plain/JSONの本文冒頭120文字を表示。機微ワード含む本文は表示抑止（完全な個人情報除去は保証できない）。
- **まだない機能**：BUFFALO経由の他端末ライブ通信先情報取得、ルーター設定や見知らぬ機種の非公開APIアクセス、HTTPS暗号化本文の復号、PCAPNG/IPv6/TCP再組立、他端末への無断導入/監視。PCAP解析データは端末RAMのみ、画面終了/背景化/消去で破棄、JS権限なし。
- **実機QA未実施**：自宅BUFFALOの機種/公式API、PCAPファイル実端末インポート、Android Debug APKインストールはまだ確認していない。テストは架空の合成パケットを使用。ユーザーに検証用サンプルPCAPを会話内で渡したが、GitHubには実ユーザーデータを含めない。詳細は[NETLAB-06A仕様](../netlab-06a-offline-traffic-inspection.md)。

## 【次】NETLAB-06B — 本人管理端末の通信先を許可付きで読み取る方法と機種別API

- 型番が分からないBUFFALOは[NETLAB-05C](../netlab-05c-router-auto-identification.md)の新画面でゲートウェイIP+UPnP型番候補を実機確認し、正式モデル/ファームと照合する。メーカーの端末一覧が存在することは、通信先IP一覧のAPIやHTTPS本文の提供を意味しない。**無いAPIを作り話しない**。
- 最初のライブ接続先機能は、本人PCの接続情報を既存PC Link相互承認/TLSピンで1回だけ渡す設計、または本人がOSで個別に承認する端末側の安全な計測を評価。どちらも無許可端末のネットワーク傍受と混同しない。HTTPS本文を復号したふりをしない。
- 現行05Bの機種別調査/実機QAを含む8タスクはSTATE`observations.deferredRouter05B.tasks`に、Game R8の8タスクは`observations.deferredGameR8.tasks`に**削除せず保存**。Release Stable/Chappy Appsカタログは別承認。

## 【履歴：06Aより前】NETLAB-05C — 型番入力なしでルーター候補を自動識別（実装/CI完了、実機未検証）

- [PR #127](https://github.com/mibesamiti-png/chappy-player/pull/127)をmain `53aa672000364c31cab4986524f649e33fdfb3e1` に統合。最終実装HEAD `ac064f571e93a9592f12e2519a4c7e3e67ab6599` で[Quick #42697064380](https://github.com/mibesamiti-png/chappy-player/actions/runs/42697064380) **67/67**、[Android Debug #42697064416](https://github.com/mibesamiti-png/chappy-player/actions/runs/42697064416) **17/17**、3ABI APK成果物あり。Windows変更なし。
- Android本体Network Labへ**「接続中のルーターを自動識別（型番候補）」**を追加。本人が管理するWi-Fiで二重承認後、Android OS現在のWi-FiデフォルトゲートウェイRFC1918 IPv4を取得。VPN/セルラーは拒否。SSDP `M-SEARCH` 一回のみ送信し、ゲートウェイと一致した応答のUPnP機器紹介XMLを16KiB/タイムアウト/同一IPに制限して任意取得。**モデル名・メーカーはUPnP自己申告の候補**で確定値ではなく、未応答ならゲートウェイIPのみ表示。AP/ブリッジでは上流ルーターが見えることがある。
- **未実装/未実機**：本物のBUFFALOによる型番自動検出成功やAndroid実機APKインストールは未テスト。モデル情報を正式な型番と照合してから機種別の**公開かつ安全な管理APIの有無**を検証する。自動ログイン、他端末の接続先IPやサイト追跡は05Cに含まない。Game R8の8タスクは保持。Stable/publicカタログ変えず。[詳細](../netlab-05c-router-auto-identification.md)。

## 【進捗更新】NETLAB-05Bの第1分割：BUFFALO端末一覧（未登録/非ペアリング機器含む）

- ユーザーからメーカー**BUFFALO**と追加要望「許可・登録していない端末も読み込む」を確認。ただし型番/ファームウェアはまだ不明。[実装PR #125](https://github.com/mibesamiti-png/chappy-player/pull/125)はmain `57e67f6252ebd105fa5712a1332f0db8f4636de7`に統合済み。最終HEAD `aa915e339e150bfd6e03e497f3bd747058e0fa85`で[Quick #42691745989](https://github.com/mibesamiti-png/chappy-player/actions/runs/42691745989) **66/66**、[Android Debug #42691746433](https://github.com/mibesamiti-png/chappy-player/actions/runs/42691746433) **17/17**成功、3 ABI APK成果物あり。
- 新規Android本体`BUFFALO端末一覧`：本人が管理するルーターの公式管理UI「デバイスコントロール」または「クライアントモニター」からIP/MAC/名前をコピー・手動貼付。**他端末のChappy登録/ペアリングなしでも管理ルーターが表示する機器は一覧に出せる**。「未登録」は不審・無断接続の判定ではなくRAM内の確認状態。32KiB、256行、128台制限。無許可パケット監視、ルーターの自動認証、通信先IP/ドメイン/本文の取得はしない。
- **今回まだない機能**：BUFFALOルーターへの自動接続・実端末の通信先IP抽出・機種別API。**未実施QA**：物理BUFFALOルーターの端末コピー・Android実機読込/Debug APK実インストール。NETLAB-05B全体は未完了、先に利用ルーター型番を確認。Game R8は8タスクを保持。Stable/公開カタログ更新なし。[詳細仕様](../netlab-05b-buffalo-inventory.md)。

## 【次】NETLAB-05B — ルーター機種別アダプターと実機互換性（8タスク）

前提：ユーザー申告のメーカーはBUFFALO。型番・ファームウェアと管理APIはまだ未確認で、NETLAB-05CのUPnP識別候補は実機ラベル/公式AirStationアプリと照合が必要。**NETLAB-05Aのソース成功は、すべてのルーターへの対応を意味しない。** 自分が管理するルーターで、本人が管理・許可を得た端末のみを対象にする。

1. 実際のルーターの型番・ファームウェアと対応APIを確認して機能別互換性表を作る。
2. HTTPS/TLSピンとread-onlyアクセスを維持した機種別アダプターを設計。
3. DHCP等の許可された端末リストから明示選択できるUI（未許可端末情報の無断蓄積なし）。
4. 接続先IP・ポート・プロトコルと通信量・DNS/ドメイン観測の有無を区別し、見えない情報を推測しない。
5. 認証情報・失効・拒否・過大応答・ロック時破棄のセキュリティを維持。
6. 非対応機種・VPN・背景化・切断・更新連打をFail Closedにする。
7. 自動テストと本人所有ルーター/Android物理接続QAを別管理。
8. 最終HEAD Quick/Android Debug CI、実機QA、Notion/GitHub引き継ぎを更新。Stableは別承認。

## 【NETLAB-05A完了記録】OpenWrtの現在接続先メタデータを1回だけ取得

- [PR #123](https://github.com/mibesamiti-png/chappy-player/pull/123) main `ffdeebd7fda5c867db56917e711a37b655d84951` に統合。最終PR HEAD `b0de4215c1541cd831bfbbdc32a56b969ed4bf78` の [Quick CI #42685427286](https://github.com/mibesamiti-png/chappy-player/actions/runs/42685427286) **65/65**、[Android Debug #42685427387](https://github.com/mibesamiti-png/chappy-player/actions/runs/42685427387) **17/17**成功。Android ARM64/ARM32/x86-64 Debug APK/互換性レポート成果物あり、Windows側変更なし。
- ホストNetwork Labに`Router Connection Lab`追加。OpenWrt HTTPS LuCI /ubus専用。管理ルーターIP・TLS証明書SHA-256指紋・読取専用資格情報・本人が情報取得を許可された対象端末IPを指定し、前景Wi-Fi・VPNなし＋独立承認後に、`luci.getConntrackList`の元方向`src`が対象IPと一致する現在の接続先IP/ポート/プロトコルのみ上限付き表示。DHCPの対象端末名はヒントであり、Android OSやアプリ名の証明ではない。
- **物理OpenWrtルーター↔Android実機テスト・Android APK実インストールは未実施。** 自宅ルーターメーカー・型番は未提示。接続先IPだけでアクセスしたサイト・アプリ名は分からず、HTTP本文/HTTPS内容/他端末の無断監視は行わない。既存NETLAB-04A/B、ASMR、Game R8元8タスクは保護。署名Stable/公開カタログ変更なし。[仕様](../netlab-05-router-connection-lab.md)。

## 【延期・計画保持】Game R8 — 本人参加のゲームサーバー・ルーム同期（8タスク・未着手）

1. 既存Game Server Lab/WSSサーバー例・ミニアプリ通信APIの権限境界を監査。
2. 利用者が選んだサーバーへの明示的な一時接続と切断。
3. ルームID・最小限のプレイヤー識別・参加/退出/状態同期。
4. メッセージ順序・サイズ/レート/同時接続上限・重複再送処理。
5. 明示的なPing/遅延、タイムアウト・可視の切断。
6. private Game Room LabのQA、背景自動接続なし。
7. オフライン・拒否・同時要求・背景化のFlutter/JS/サーバー回帰。
8. 最終HEAD CI/Debug APKと実機QA/Stableを分離しGitHub/Notion更新。

## 【NETLAB-04B完了記録】本人PCとの安全な1回通信量読込（ソース/CI）

- [PR #121](https://github.com/mibesamiti-png/chappy-player/pull/121)をmain `664802dba4b899d0334ef4ba845c96fdfe0a9861` に統合。最終HEAD `7aff08d5cfbd3145f78f43ce6546b44e92b9ff97` で[Quick #42676947378](https://github.com/mibesamiti-png/chappy-player/actions/runs/42676947378) 64/64、[Windows #42676947845](https://github.com/mibesamiti-png/chappy-player/actions/runs/42676947845) 28/28、[Android Debug #42676947259](https://github.com/mibesamiti-png/chappy-player/actions/runs/42676947259) 17/17成功。Windows EXE＋起動CMDとAndroid 3 ABI Debug APK成果物生成。
- 本人PCの明示起動、専用 `traffic=1` QR-v3/TLSピン/P-256相互認証、PC側の独立 `TRAFFIC` 入力とAndroid前景別承認。5〜30秒の全NIC合算RX/TXカウンターだけを1回取得、RAM表示・手動消去。署名スコープ `pc.traffic.read`、再送/失効/ネットワーク切替/停止・VPN経路を拒否。NETLAB-04A手動JSONも残した。
- **Android↔Windowsの物理2台Wi-Fi通信実機QA未実施。** 全NICを合計するのでWi-Fi以外のNIC計数も含みうる。他人の端末/パケット本文は監視しない。04A QA、PC Link 0/15＋媒体0/13、R7 0/12は変更なし。署名Stable/公開カタログも変更なし。[詳説](../netlab-04b-consented-traffic-once.md)。

## 【履歴：04B実装前の8タスク】NETLAB-04B — 管理PCのQR署名付き直接読込

NETLAB-04Aの完成範囲は**ファイル経由**。PCに本人承認済みのWindows Companionを置く方式で、次はそのPCの通信量をスマホから安全に取得する。本バッチでもルーターや他人の端末のパケット本文は取得しない。Game R8は引き続き保持する。

1. R4CのQR-v3 status署名/TLS pinとR04A通信量カウンターを監査。
2. 新規`pc.traffic.read`署名スコープ、QR明示オプトイン、短命nonce/再利用拒否。
3. Windows本人のTRAFFIC別承認とAndroid本人の前景別承認。
4. 全NICの匿名化された通信量のみ、回数・サイズ・期間の上限付き返答。
5. Androidホストに一回限りの直接読込UIと結果消去・中止を導入。
6. 誤認証・期限・再送・Wi-Fi切替・背景化・切断時にFail Closed。
7. Python/Dartの共有検証ベクトル・localhost結合/ウィジェット自動回帰を追加。
8. 最終HEAD Quick/Windows/Debug APK CIを確認し、PCとAndroid実機QA・Stable公開は別ゲートで管理。

## 【NETLAB-04A完了記録】管理Windows PC交通量ファイル読込

- [PR #119](https://github.com/mibesamiti-png/chappy-player/pull/119) main 38c35433ab793b2dfff9bf4726d66fbd4cc3b2f9に統合。[Quick #42668253644](https://github.com/mibesamiti-png/chappy-player/actions/runs/42668253644) 64 / [Windows #42668253778](https://github.com/mibesamiti-png/chappy-player/actions/runs/42668253778) 28 / [Android Debug #42668253834](https://github.com/mibesamiti-png/chappy-player/actions/runs/42668253834) 17ステップ全成功。Windows EXEとCMD、Android Debug APK ARM64/ARM32/x86-64あり。
- Windows PC自身の全ネットワークインターフェース通信量を本人TRAFFIC入力後だけ新規JSONへ書込。Android本体Network Labで選択→厳格16KiB形式・合計検証→合計/平均/ピーク/推移をRAM表示。
- **パケット/接続先/他のLAN機器の通信本文なし、JSONは未署名、ファイル手動移送（リアルタイムなし）**。Windows/Android実機QA未実施、R7 0/12、PC Link 0/15+0/13継続。署名Stable/公開カタログは変更なし。[仕様](../netlab-04a-remote-traffic-report.md)。

---

## 【履歴：04A実施前】Game R8 — ルーム同期と本人参加型通信（8タスク・未着手）

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

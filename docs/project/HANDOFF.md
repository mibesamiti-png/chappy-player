# Chappy Player — 単一チャット高速開発 v2 最新引き継ぎ

## 【最新】CAMREC-16 Debug v0.1.7（2026-11-11）— ソース/公開Debug統合、実機録画は未検証

- **再引き継ぎで検証**：Chappy Player [PR #142](https://github.com/mibesamiti-png/chappy-player/pull/142) は main `27131a0dfe0031b0803ae310d12f4bdd954b55ff` に統合済み。最終実装HEAD `c7eb663d65ce91f590e13419919786f59a4badc3` に対し [Quick CI 76/76](https://github.com/mibesamiti-png/chappy-player/actions/runs/42876978962) と [Android ARM64/ARM32/x86-64 APK 17/17](https://github.com/mibesamiti-png/chappy-player/actions/runs/42876978926) 成功。
- **録画画面の説明ON/OFF**：DEBUGヘッダーから外して最下部の「スマート録画・確認設定」折りたたみ内へ移動。Chappy Apps一覧のDebug/Stable横にある別の説明表示切り替えは変更なし。
- **開始不具合の改善**：録画本体の対応確認が非同期で未完了でも開始ボタンを無言で無効化しない。対応未確認時は、明示的に設定を開き、Debug本体更新または「通常録画」選択を案内する。**実機で開始できない根本原因が解消したと確定したわけではない**。ユーザーは前版で「開始を押しても開始されなかった」と報告。
- **通知状態**：明示開始した画面OFF録画のForeground Service通知は、実際にCameraXが静止でpauseしたとき「一時停止中」、動作検出でresumeしたとき「録画中」に切り替える。通知の「録画を停止」操作、Androidカメラ/マイク使用中表示、通知・権限チェックは維持。通常録画中・暗転録画の表示全般を同じ通知として扱わない。
- **公開Debug**：Chappy Apps [PR #11](https://github.com/mibesamiti-png/chappy-apps/pull/11) → main `1dd3736f7eb0e19bee47438bb757bafe0f708d31`。 [カタログCI 7/7](https://github.com/mibesamiti-png/chappy-apps/actions/runs/42878670602) 成功。 `local.chappy.recorder` Debug **v0.1.7**。Stable版変更なし。利用は新しいDebug APKを導入し、Chappy Apps→Debug→更新→Recorder v0.1.7。
- **次の確認（未実施）**：実機で「通常録画」を短時間試し、開始失敗文言・カメラ/マイク許可・MP4保存を確認。その後、標準スマート録画の静止5秒→一時停止→動作再開→Android通知同期→通知から停止・ファイル確定・保存を検証。確認省略設定OFF/ONとアプリ再起動後の維持も確認。古いDebug APKや署名不一致を考慮し、データを削除せず更新する。**実機QA 0件。Stable公開禁止。**
- 短期優先度は実機録画の原因特定と停止・保存の保証。プリ録画R3やAI R4は延期。GitHub main/PR/CIが正本で、Notionは確認後手動ミラーする。


## 【最新】CAMREC-15 Recorder UX v0.1.6（2026-11-11）— Debugで登録済み／実機未検証

- **ユーザー要望を実装済み**：スマート録画の標準を「静止時pause・動けばresume」、静止判定の標準を**5秒**に変更。Android CameraX・画面OFF録画サービス・Flutterのバリデーションとも5秒に対応。空き容量カードをコンパクトに再配置。
- スマート録画設定を**プライベート動画の後＝一番下に移動**し、初期状態は閉じる。内部の「毎回『今回の録画を許可』を確認する」で録画ごとのChappy Player独自確認を選択可能。初期値はON（毎回確認）。OFF変更時に限って本人に一度だけホスト確認し、Android本体のSharedPreferencesに保存。以後の本人による録画ボタン操作でのホスト確認は省略できる。**OSのカメラ/マイク/通知許可、画面OFF録画の通知と停止操作、Androidのプライバシー緑点はそのまま**。他のミニアプリに一般的な確認省略権限を渡さない。
- Recorderヘッダーの「DEBUG」横に「説明 ON/OFF」ボタンを追加。長い補足説明だけをまとめて切替。Chappy AppsのDebug/Stable切り替えの隣にも説明文の表示/非表示ボタンを追加。
- [Chappy PlayerソースPR #140](https://github.com/mibesamiti-png/chappy-player/pull/140) → main `a4f94b2239ce3eb3d29cc2edc26429fbaf8deb35`、[Quick CI 76/76](https://github.com/mibesamiti-png/chappy-player/actions/runs/42872432652)、[Android 3ABI 17/17](https://github.com/mibesamiti-png/chappy-player/actions/runs/42872432385) **成功**。
- [Chappy Apps Debug PR #10](https://github.com/mibesamiti-png/chappy-apps/pull/10) → main `104c1fd1f8e336a52aebd4c8faca2d64b169686e`、[カタログ検証7/7](https://github.com/mibesamiti-png/chappy-apps/actions/runs/42872700793)成功。Recorder Debug `v0.1.6`、Stable 2本/Debug 9本、従来のStable無変更。インストールは新しいDebug APK→Chappy Apps→Debug→更新→Recorder v0.1.6。
- **実機カメラ確認はまだ0件**。次は画面OFF録画、通知停止、5秒でpause・動いてresume、MP4確定、権限確認OFFの持続・再ON、音声ON/OFFを確認。長時間録画の前に空き領域を十分に確保する。現行の1GiB/ファイル上限は維持。
- 次の機能実装よりも実機QAを優先。CAMREC-14 R2の画面OFF録画設計・NETLAB延期計画・プリ録画R3候補は維持。


## 【復旧・最新】CAMREC-14 R2：画面OFF録画コード統合済み／実機QA待ち（2026-11-11）

- 途中停止したように見えた前作業を最新GitHubから再確認。**画面OFF録画PR #138は2026-11-10にmainへ既にマージ済み**（`05fba83784845e466bdd6d3d387a352a8009ff64`）。`ChappyCameraService.kt` にユーザー明示同意によるAndroid camera/mic Foreground Service、録画中のOS通知と停止アクション、`NativeVideoRecorder.kt` のCameraXサービス所有・録画確定処理がある。
- 最新main [Quick CI #42826356725](https://github.com/mibesamiti-png/chappy-player/actions/runs/42826356725)と[Android互換APKビルド #42826356999](https://github.com/mibesamiti-png/chappy-player/actions/runs/42826356999)はともに**成功**。Android Debug成果物はARM64/ARM32/x86_64別。実機で画面OFFの撮影と通知停止が働いたことは**未検証**。結果0件、機種別確認が必要。
- [Chappy Apps PR #9](https://github.com/mibesamiti-png/chappy-apps/pull/9)で**Chappy Recorder Debug v0.1.5**を公開ライブラリに登録済み。Stableは変更なし。本人が新版Debug APKと`Chappy Apps → Debug → 更新 → Chappy Recorder`を使用。**録画前に明示選択・許可**し、録画中は通常のAndroid通知に停止ボタンを表示。物理画面OFF中はOS緑点が視覚的に見えなくなるが、OSプライバシー監視を無効化する機能ではない。
- 本体の古い`STATE.json`がR1/未実装を指していたため、本引き継ぎでR2のソース統合・CI・配布事実へ更新。次は`docs/camrec-14-screenoff-recorder.md`の**実機QA**（30秒〜10分/音声ON-OFF/ホーム切替/画面OFF/再点灯/通知停止/動き検知/MP4確定）を実施。**署名Stable未配布、プリ録画R3未実装**。NETLAB-06BとGame R8延期事項は保持。
  

## 【最新】CAMREC-13-R1 スマート録画｜ソース/Androidビルド成功・実機録画未検証｜2026-11-10

- ユーザー採用：「長時間録画は動きがないとき休止/終了、動いたら再開。静止時間と感度を調整」。**動き検知による録画制御R1はソース実装・CI完了**。Chappy Player [PR #136](https://github.com/mibesamiti-png/chappy-player/pull/136) → main `8c31a68e667799ef505393f621855e4a7f3d71db`。実装元HEAD `2619f911be81c8339be886439e397a17485b421c`、[Quick CI 74/74](https://github.com/mibesamiti-png/chappy-player/actions/runs/42721111102)、[Android互換APKビルド 17/17](https://github.com/mibesamiti-png/chappy-player/actions/runs/42721110750) **成功**（ARM64/ARM32/x86_64）。
- `NativeMotionAnalyzer.kt`：CameraX ImageAnalysisのY平面16×12点/最大4Hz・一様な露出変化を補正・2サンプル連続の動き検出。`NativeVideoRecorder.kt` が映像を保存する `VideoCapture` と同時使用し、**通常／静止中pause→動いたらresume／静止時間で録画stop** を選べる。10〜300秒、感度0〜100。解析エラーでは勝手に静止と判断せず録画を継続。非対応カメラ構成は明示エラー。rawフレームの保存・外部送信なし。
- Chappy Recorder `v0.1.4` を [Chappy Apps公開Debug PR #8](https://github.com/mibesamiti-png/chappy-apps/pull/8) で追加、公開main `f3dc66751239da98e382624daf594a84264e8c5d`、[カタログCI 7/7](https://github.com/mibesamiti-png/chappy-apps/actions/runs/42722599197) 成功。**Stable 2本・Debug 9本は維持**、Debug Recorderだけv0.1.3→v0.1.4。旧プレイヤー本体ではスマート録画ボタンを無効にし、通常録画は利用できる。本人がChappy Apps→Debug→更新して選択インストールする。
- **R1はまだスマホ実機で動き検知録画していない**。Quick/Androidビルド成功と実機撮影成功は別。暗転のハード音量キー、既存MP4保存/復元を含めQAが必要。以前のユーザー報告「起動とHTTPS通信は成功」は別件であり、今回のカメラテストに流用しない。
- **画面OFF・他アプリ利用中の録画は未実装**。R1は以前と同じく`Activity.onPause`で停止。次はCAMREC-14-R2でAndroid Camera Foreground Service/録画中通知/停止ボタンを設計。プリ録画・AIはR3/R4の候補。OSの緑色インジケーターの無効化はしない。詳細 [CAMREC-13仕様](https://github.com/mibesamiti-png/chappy-player/blob/main/docs/camrec-13-smart-recording.md)。
- NETLAB-06Bの元タスク8本は `STATE.json.observations.deferredNetlab06B`、Game R8の延期事項も維持。署名Stable公開はユーザーの別途承認が必要。


## 【実機速報】起動・HTTPS通信はユーザー確認で成功｜2026-11-10 JST

- ユーザー実機報告：「一旦起動はしたしHTTPS通信が出来た事だけ報告しとくー」。**アプリ起動 = ユーザー報告で成功、HTTPS通信 = ユーザー報告で成功**。コード・CIの成功とは独立した実機スモーク確認として記録。
- **使用したAPKバージョン、Debug/Stable、HTTPSの実行画面/URL、ミニアプリか本体かは未確認**。記録上は推測しない。実URL・個人の通信データ・端末固有情報をGitHubへ記載しない。
- 従来のNETLAB実機チェックリスト **QA-01～QA-09については完了判定0/9** のまま。QA-01は起動のほかセルフチェック4項目実行・レポートコピーが必要。HTTPS通信成功だけではNetwork Labの他の操作やルーター識別/PCAP解析がPASSにならない。
- [Chappy QA Checklist v0.1.0](https://github.com/mibesamiti-png/chappy-apps/blob/main/debug/chappy-qa-checklist-v0.1.0.chappy) は公開Debugライブラリに登録済み。ユーザーが利用する場合、今回の起動/HTTPSは速報として残し、残りのチェック結果は本人の実際の操作に基づいて入力する。
- 新機能開発は実機デバッグ優先で一時停止中。実機操作は今後、確認できた順にGitHub STATE/HANDOFFとNotionへ記録する。



## 【最新】DEBUG-QA-CHECKLIST-01｜Android実機QAミニアプリ・公開Debugライブラリ9本｜2026-11-10

- 要望：「デバッグ内容のチェックリストをミニアプリに追加」「今後のミニアプリ系はDebugライブラリへ」。**Chappy QA Checklist v0.1.0**を `sample_apps/debug_checklist/` として実装し、公開Chappy Appsの**Debugだけ**に追加。[プレイヤー実装PR #133](https://github.com/mibesamiti-png/chappy-player/pull/133) → main `f8e239abff214fb77bee352a7248067d685470e6`、[Quick CI 71/71](https://github.com/mibesamiti-png/chappy-player/actions/runs/42712257849)。
- [Chappy Apps公開Debug登録PR #7](https://github.com/mibesamiti-png/chappy-apps/pull/7) → `c0e1eb45dafd891fdf903170de3d042c8197dd1f` に統合、[公開カタログ整合性CI 7/7](https://github.com/mibesamiti-png/chappy-apps/actions/runs/42712891326)成功。**Stable 2本・Debug 9本**。`local.chappy.qa_checklist` v0.1.0、SHA256 `26699be9aad879f96cb7dd85c601b41896eaf8d787b74c92f4da0ba47f0fb1db`、19,579 bytes。`https://raw.githubusercontent.com/mibesamiti-png/chappy-apps/main/debug/chappy-qa-checklist-v0.1.0.chappy`。
- Chappy Player → **Chappy Apps（公開ライブラリ）→ Debug → 更新 → Chappy QA Checklist追加**。アプリを開くと `docs/qa/NETLAB_DEBUG_2026-11-10.md` に対応した **QA-01～QA-09** の操作・期待結果・判定（未実施／成功／失敗／保留）が出る。進捗・メモ・レポートコピー・リセット付き。**成功判定は手動のみ**、CI成功は実機PASSに流用しない。
- **権限 `[]`**。ネットワーク/PCAP/ルーター/カメラ/マイク/ファイルなどのnative実行機能なし。判定だけlocalStorageへ保存、メモ・Android OSバージョン・Run番号は一時メモリのみ、共有前に個人情報確認。通常のユーザー選択による公開Debugからのダウンロードであり、本体への無断自動インストールやStable公開なし。
- 既存の**非公開**PC Control Lab／PC Transfer Lab／Browser Labなどは公開していない。今後も公開可能な、レビュー済みミニアプリだけDebugチャンネルへ追加する。非公開試作・機密情報・権限の強いツールは確認なしに公開しない。
- 実機QA全9項目は**0/9・未実施**。WebView動作、localStorage継続、クリップボード、端末セルフチェック、BUFFALO型番/UPnP、ファイルピッカー/合成PCAPなどはスマホ実機確認待ち。NETLAB-06B新機能追加は一旦停止、既存Game R8延期8タスク・Stable・既存機能を保全。次チャットではmain/PR/CIの最新値を再取得してから再開。



更新: 2026-11-10。NETLAB-06Aデバッグ回帰と実機9項目QAキットの実装mainスナップショット f5c69477eea37d3fd6f3d810368922332bdbf45e。Quick68/Android17は成功、実機QAは0/9。NETLAB-06B新機能は一時停止してデバッグ優先。再開時は必ず最新main・PR・CIを再取得。

## 【最新：デバッグ優先】Chappy Player Network Lab 実機QAキット＋解析品質修正｜2026-11-10

- ユーザーが「ここまでの機能追加はいったん止めてChappy Playerをデバッグ」と指示したため、**NETLAB-06Bの新機能は一時停止し、機能回帰・Debug APK・スマホ実機テストを優先**。
- **コード改善PR #131**（https://github.com/mibesamiti-png/chappy-player/pull/131）をmain `f5c69477eea37d3fd6f3d810368922332bdbf45e` に統合。実装最終HEAD `b7a8e1830907257f7016e36380b2934d3903e9cd` の [Quick CI #42708245092](https://github.com/mibesamiti-png/chappy-player/actions/runs/42708245092) **68/68**、[Android Debug #42708245065](https://github.com/mibesamiti-png/chappy-player/actions/runs/42708245065) **17/17**成功。ARM64/ARM32/x86-64のDebug APKと互換性レポート成果物あり。
- **確認・修正した内容**：PCAPパーサでDNS**応答**を問い合わせと誤表示しない／IPv4のMFフラグを含む分割片は完全なHTTP/TLSとして扱わない／未対応パケットが160件を超えただけでは表示省略の警告を出さない。合成パケットのDNS・VLAN・TLS SNI・形式異常に加えて350件のシード固定ランダムパケットを回帰検証。新しいルーター取得権限や常時通信監視は追加していない。
- **実AndroidのQAは0/9・未実施**。手順は [NETLAB DEBUG 9項目](../qa/NETLAB_DEBUG_2026-11-10.md)。起動/セルフチェック/Network Lab/BUFFALO手動端末一覧/ルーター型番候補/PCAP選択・平文ON/OFF/不正PCAP/背景化・結果破棄をスマホで確認してもらう。ChatGPT内で**完全合成の6パケットPCAP＋不正2種入りZIP**を生成した（GitHub公開CIへの個人PCAP持ち込みはなし）。
- **安定版を勝手に消さない**：Debug署名と現在のインストール済みAPKの署名が異なる場合、上書きインストールできない。削除はデータ消失リスクがあるので、別テスト端末またはバックアップ確保後に確認。Debug APKの生成成功は実機インストール成功と異なる。
- **未実装・未検証**：実BUFFALOのUPnP応答/型番認証、BUFFALOルーターの他端末通信先のライブ監視、暗号化HTTPS本文の解析、実AndroidでのPCAP画面確認。既存Game R8延期8タスク・ASMR・OpenWrt・PC Link・署名Stable・公開カタログは維持。
- 本デバッグ回のGitHub正本：[STATE](STATE.json) / [ROADMAP](ROADMAP.md) / [実機QA手順](../qa/NETLAB_DEBUG_2026-11-10.md)。Notionは状況ミラー。

---

## 【履歴：デバッグ回より前】NETLAB-06A 許可を得たPCAPの通信先・内容解析｜ソース/Quick68/Android17 CI統合・実機未検証｜2026-11-10

- ユーザー希望：「他の接続端末がどこにアクセスしているか、通信内容も分かるように」。BUFFALO型番/ファーム未確認で管理API経由の他端末ライブ監視は実装できないため、**本人管理・利用許諾済みのキャプチャファイルに限るオフライン解析**を先行。**所有者に知られず他端末の通信を取る機能ではない**。暗号化HTTPS/QUIC本文は復号できない。
- [実装PR #129](https://github.com/mibesamiti-png/chappy-player/pull/129) をmain `3efe4caa0536c5dedec5a51dd7add364efd93b5e`へ統合。最終実装HEAD `f5c2ce5a04bcacd6e96319f355311d07605d31ef`の[Quick CI #42702059765](https://github.com/mibesamiti-png/chappy-player/actions/runs/42702059765) **68/68**、[Android Debug #42702059838](https://github.com/mibesamiti-png/chappy-player/actions/runs/42702059838) **17/17**成功。ARM64/ARM32/x86-64 Debug APKと互換性レポートあり。Windows側変更なし。
- **Android本体Network Lab →「通信先・平文内容をPCAPから解析（本人許可）」**：本人管理・対象端末所有者許可のチェックと毎回の確認後、`.pcap/.cap`をファイルピッカーで手動選択。classic PCAP 2.4のEthernet/Raw IPv4（2MiB/2500パケット/160件上限）に対応し、IPv4送信元・宛先IP/ポート、TCP/UDP、DNS問い合わせ名、TLS ClientHello SNI候補、平文HTTPのメソッド/パス（クエリは表示しない）/Hostを一覧に表示。送信元IPv4で絞り込み可能。
- **通信本文の制限**：初期OFFのオプションを明示ONにした場合、単一パケットの平文HTTP `text/plain` / `application/json` の短い冒頭120字プレビューのみ表示。機微ワードがあれば非表示（完全なマスキング保証なし）。Cookie/Authorizationヘッダーは表示しない。HTTPS/TLS/QUICは暗号化のため本文を表示できない。PCAPNG/IPv6/分割TCP再組立は未対応、DNSクエリは実アクセスの証拠ではない。
- **安全/QA**：Android本体専用、別端末の監視権限・VPN・root・パケット傍受・MITM・JSミニアプリ権限・自動外部送信・永続ログなし。背景化/画面終了/消去で結果と同意を破棄。自動テストは合成PCAPのみで実通信データはCIに入れていない。**実Android APKインストール、BUFFALO実機のルーターからのデータ、PCAPファイルの現物読み込みは未実施**。
- **次NETLAB-06B**：既存NETLAB-05CでBUFFALOの型番候補を実機で確認→公式・読み取り可能な管理APIがあるか調査。なければ本人PC/対象端末側の明示許可付き通信先メタデータ単発取得を設計。以前のNETLAB-05Bの未完8タスクとGame R8の8タスクはSTATE observationsに保存して継続。Stable/公開カタログ未変更。
- [仕様/限界](../netlab-06a-offline-traffic-inspection.md) / [STATE](STATE.json) / [ROADMAP](ROADMAP.md) / Notion手動ミラー。GitHub main/PR/CIが正本。

---

## 【履歴：06Aより前】NETLAB-05C ルーター自動識別（Wi-Fi Gateway + UPnP公開モデル候補）ソース/CI統合済み・実機未検証｜2026-11-10

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

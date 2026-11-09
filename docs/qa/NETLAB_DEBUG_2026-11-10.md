# Chappy Player｜Network Lab 実機デバッグ手順（2026-11-10）

**作業目的：機能追加の前に、最新Android Debug版の起動・権限・通信表示・画面復帰・データ破棄を実機で確認する。**

## 検証対象・ソースとの区別

- 対象GitHub: [Chappy Player](https://github.com/mibesamiti-png/chappy-player)。作業開始時のmainは `fa630d642cbb3b249fcfa9432eef73607a7d0988`。開始時の既存Quickは [68/68](https://github.com/mibesamiti-png/chappy-player/actions/runs/42703961058) 、Android Debugは [17/17](https://github.com/mibesamiti-png/chappy-player/actions/runs/42702970587) で3 ABI APK成果物あり。**新しいQA修正版のAPKはそのCI成功が確認できてから使用**。PR/HEAD/CIを再取得して記録する。
- GitHubの**Build Compatibility APKs**ワークフローにある `ChappyPlayer-Android-ARM64` を通常の現行ARM64スマホで選び、ZIPからAPKを取り出す。ARM32/x86-64用は端末ABIが適合するときだけ。
- **Debug APKは安定版と署名が異なる可能性があるため、上書きインストールが失敗しても直ちに既存Chappy Playerをアンインストールしない**。インストール済みミニアプリや録画データの消去防止のため、別の試験端末か署名整合性が確認できた環境を利用する。アプリのデータを保持する必要があれば先に公式のバックアップ・エクスポート機能で安全性を確認する。
- 実機で確認していない項目をPASSにしない。Android/実BUFFALOのUPnPレスポンス、SDK/権限差、ファイルピッカー、バックグラウンド復帰は**CI PASSとは別**。

## スマホ操作チェック（QA-01～QA-09）

| ID | 操作 | 期待結果 | ユーザー実機 |
| --- | --- | --- | --- |
| QA-01 | Debug APKを起動してホーム→端末セルフチェック→実行→結果をコピー | 起動成功。セルフチェック4件の実測PASS/FAILが分かり、コピーできる（4件成功を前提としない） | 未実施 |
| QA-02 | ホーム→Network Labを開き、各機能のボタンと戻る操作を確認 | 画面が落ちず、ブラウザ/端末一覧/通信解析/ルーター識別へ移動できる | 未実施 |
| QA-03 | 「接続中のルーターを自動識別」→チェック前→同意して1回 | 同意前は探索されない。Wi-FiかつVPNなしの場合、IPv4ゲートウェイ候補。UPnPがなければ型番不明（正常系）。外部サイト履歴や他端末通信先は表示しない | 未実施 |
| QA-04 | ネットワークをWi-Fi→モバイルまたはVPNに変更／途中でアプリ背景化 | 取得拒否または結果破棄。画面復帰で古い型番・住所・端末情報を残さない | 未実施 |
| QA-05 | BUFFALO端末一覧：管理するルーター確認にチェックし、**自作の検証行**を貼る | `192.168.11.10, AA:BB:CC:DD:EE:01, TestPhone` と `192.168.11.20, AA:BB:CC:DD:EE:02, TestLaptop` の2台を認識。MAC識別済みトグル/未登録表示・削除が動く | 未実施 |
| QA-06 | 「通信先・平文内容をPCAPから解析」→同意前にボタン、承認前にキャンセル | 同意前はファイルを読まない。キャンセル後は結果に変化がない | 未実施 |
| QA-07 | **合成PCAP**を選択し、本文プレビューOFFで解析 | DNS `example.org`、TCPのHTTP `GET /help`・`POST /demo`、TCP/443暗号化、UDP/443 QUIC候補などが表示される。本文は表示されない | 未実施 |
| QA-08 | 平文プレビューON→合成PCAPを再選択→結果を確認→結果消去 | POST本文 `Hello from Chappy Lab!` が表示される（デバッグ用サンプルのみ）。消去・背景化後、結果と同意が破棄される | 未実施 |
| QA-09 | 手動端末一覧/PCAPを大量/異常データに変えたり、一度画面を戻して開き直す | サイズ制限や形式エラーが明示され、クラッシュしない・不要な状態が復元しない | 未実施 |

**安全なテストデータ：** この一覧で指定するIP/MAC・DNS・HTTPパスは架空の合成値のみ。実ユーザー/家族の通信ログ・ルーター認証情報・MACアドレスをGitHub公開Issueやスクリーンショットへ貼らないこと。

## 解析結果を読み間違えないために

- クライアントモニターの未登録 ≠ 不正侵入の確定。MACランダム化や家電・家族端末が原因になる場合がある。
- DNS質問と「そのサイトを訪問した」は同義ではない。DNS**応答**を「問い合わせ」と誤表示しないためのコード回帰修正も検証対象。
- SNIは取得できた場合のみの自己申告メタデータ。HTTPS本文の復号はこのアプリにはない。
- **実BUFFALOから未登録端末の通信先をライブ取得する機能は未実装**。PCAP解析は本人が明示選択したローカルファイルのみ。
- 検証するファイルは2MiB以下のclassic PCAP（Ethernet/Raw IPv4）。WiresharkのデフォルトPCAPNGはこの版の対象外。

## 報告テンプレート

```text
Chappy Player 実機QA
Debug APK / GitHub run:
端末のAndroidバージョン: （機種名は任意）
インストール: OK / 上書き不可 / 未実施
起動・セルフチェック: X/4
QA-01: PASS/FAIL/未実施
QA-02: PASS/FAIL/未実施
QA-03: PASS/FAIL/未実施　（UPnPなし/型番不明も正常）
QA-04: PASS/FAIL/未実施
QA-05: PASS/FAIL/未実施
QA-06: PASS/FAIL/未実施
QA-07: PASS/FAIL/未実施
QA-08: PASS/FAIL/未実施
QA-09: PASS/FAIL/未実施
再現手順・発生したエラー:
※ パスワード・認証トークン・実MAC/実IP・本物のPCAPは添付しない
```

## 実装側の確認

- 静的・Flutter Quick CI（回帰テスト含む）とAndroid Debug 3 ABI CIが**新しい正確なHEAD**でそれぞれ成功したことを記録する。
- Windows/MiniApp/Stableを変更しない。実機QA前に公開Stableをリリースしない。
- 検証結果・未実施・既知問題を `docs/project/STATE.json` と `docs/project/HANDOFF.md` の正本へ更新し、Notionへミラーする。

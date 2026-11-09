# NETLAB-06A — 許可を得た通信キャプチャのオフライン解析（通信先・内容の理解）

## 要望と実装範囲

ユーザー希望：「他の端末がどこにアクセスしているか、通信内容も分かるようにしてほしい」。そのうち**ユーザーが管理/許諾を受けている端末や検証環境**のデータを解析できる部分を先行実装。BUFFALOルーターの機種・ファームウェアが未提示で管理APIも未確認のため、**他の接続端末の通信をリアルタイムに自動取得する機能は実装していない**。PCAPファイルを手動で持ち込む方式であり、無断傍受・トラフィックを横取りする権限をAndroidへ追加しない。

既存のNETLAB-05BのBUFFALO未登録端末一覧（本人の管理画面から手動コピー）は維持し、その「IP/MAC一覧」だけから閲覧サイトや通信内容を推定しない。NETLAB-05CゲートウェイとUPnP型番候補も別機能。

## 新機能

1. Android本体 Network Lab → **通信先・平文内容をPCAPから解析（本人許可）** を開く。
2. 管理・解析許諾があるファイルだけを扱うことをチェック、毎回ファイル選択前に追加確認。ファイルピッカーで `.pcap` / `.cap` を**ユーザーが明示選択**。
3. `classic PCAP v2.4` の**Ethernet（DLT 1）/Raw IPv4（DLT 101）**だけを、AndroidホストFlutterのメモリ内で解析。ファイルサイズ最大2MiB、最大2500パケット、画面上最大160件、ヘッダー/パケット長/VLANの境界チェック、IPv4の非先頭フラグメント除外。**PCAPNG/IPv6は未対応**。
4. パケットから **送信元IPv4 → 接続先IPv4:ポート、TCP/UDP、DNSで問い合わせたドメイン名（実アクセス先の証拠ではない）**、単一パケットに収まった**TLS ClientHello SNIホスト名（取得できた場合のみ）**、平文HTTPのメソッド/パス（クエリ文字列は省略）/Hostを表示。送信元IPでの絞り込みも可能。
5. **「平文HTTPの短い本文も表示」オプションは初期OFF**。再度ファイルを読み込む際に本人が有効化した場合のみ、単一パケット中の `text/plain` / `application/json` 本文を最長120文字プレビュー。password/token/API key/cookie/session/email/phone等を含む可能性があるものは本文を非表示。これは保証済み機微情報マスキングではないので**本人管理のテスト用PCAPが推奨**。HTTPヘッダーのCookieやAuthorizationは表示しない。
6. TLS/HTTPS/QUICなど暗号化された本文は**読み取らず、「暗号化・本文は読めない」と明示**。暗号化通信を復号する機能、端末への証明書インストール、MITM、ネットワークの透過傍受、無断他端末PCAP取得はなし。DNSがDoH/DoT、TLSがECH、VPN利用、TCPセグメント分割時など、解析できる情報は減少する。
7. ファイルデータは**ローカル端末のRAMのみ**に保持し、バックグラウンド・画面終了・消去操作で表示結果と本人の承認を解除。通信データの保存・外部送信・常時監視・ルーターへの接続・mini-app JavaScript特権はなし。

## 実装

- `lib/core/pcap_inspector.dart` — バイト長/レコード制限、安全な部分プロトコル解析。
- `lib/screens/traffic_inspection_page.dart` — 本体専用の本人承認・ファイル選択・結果一覧。
- `lib/screens/network_lab_page.dart` — 導線。
- `test/pcap_inspector_test.dart`、`test/traffic_inspection_page_widget_test.dart` は**生成した合成パケットのみ**を使用。実ユーザーのパケット/アカウント情報をCIに含めない。
- `tools/test_pcap_inspection_boundary.py` をQuick CIのセキュリティプリフライトに追加。

## 現在のBUFFALOでリアルタイム解析するための残条件

- メーカー公式資料では管理画面の「デバイスコントロール」「クライアントモニター」で接続端末のIP/MACの確認方法を記載。**すべてのBUFFALO型番で1台ごとの外部接続先や本文が取れるとの公式根拠はない**。[BUFFALO公式FAQ](https://www.buffalo.jp/support/faq/detail/15741.html)
- Androidの[VPNService](https://developer.android.com/reference/android/net/VpnService)は**そのVPNを動かすAndroidデバイス内のトラフィック**をOSの承認で取得する別技術。無関係の端末を同じWi-Fiにつなぐだけでその通信を取得できるわけではない。今バッチではVPNServiceを追加せず既存Network LabのWi-Fi/VPN境界を維持。
- 次の機種別自動通信先表示は、**ユーザーのBUFFALO型番・ファームウェアと安全な読取API**が実際に確認できてから実装する。管理ルーターがデータを提供しないなら、本人が選んだファイル/明示同意済みの端末側アプリからの解析を採用する。TLS暗号化した本文はルーターでは復号できない。
- Quick CIとAndroid Debug 3 ABI合格と、BUFFALO/Android/PCAPファイルの**物理実機QA**は厳格に区別する。Stable/公開Chappy Appsカタログは手動承認まで変更しない。Game R8延期の8タスク、ASMR、OpenWrt 05A、BUFFALO 05B/05Cは保持。


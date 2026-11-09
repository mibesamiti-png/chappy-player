# NETLAB-04B — 本人Windows PCの通信量をQR-v3 + pinned TLSで1回だけ直接取得

状態: **開発PR #121 / ソース試作。CI最終HEAD・Android/Windows実機QAは別判定**。NETLAB-04Aの手動JSONインポートは維持する。Game R8も計画として保持する。

## 取得できる情報

PCの所有者が明示的に実行したWindows Companionの `--traffic-read-once` だけが、PCの **全NIC合算** RX/TX byte counters の5〜30個の1秒差分を測る。結果は既存の `chappy.remote-traffic.v1` 厳格契約を使用する。送信先IP、SSID、インターフェース名、MAC、プロセス名、サイト、パケットヘッダーや内容、別端末のトラフィックは収集しない。VPN/Ethernet/仮想NICも**そのPCのカウンター合計**に含まれる可能性がある（Wi-Fi専用カウンターではない）。

## PC → Android 所有者が毎回行う手順

1. Windows上で `Start-ChappyIdentitySetup.cmd`（未作成時のみ本人が端末鍵を作成）を準備。
2. 最新**未署名Debug Windows ZIP**の `Start-ChappyTrafficReadOnceV3.cmd` を本人が明示起動。状態チェック後に前面コンソールとQR-v3 `traffic=1` を表示する。ローカルの既定値は10秒。CLIでは `--traffic-read-seconds 5..30` の範囲に限る。
3. 同じWi-Fiに接続し、Chappy Player本体 → Network Lab → 本人PC発見 → QR-v3スキャン。mDNSの機器名だけでは信頼しない。IP/portとQRを一致確認し、QR TLS証明書SHA-256 pin、PC固有P-256公開鍵を検証する。
4. PC画面で、本人確認の別の `YES` を承認。Androidでも専用の端末鍵署名を承認。認証が完了しても権限ゼロ。
5. Androidで「通信量を1回だけ直接取得」を選択。PC側で**別のTRAFFIC**入力をし、PCの新しい **`pc.traffic.read`** 署名をAndroidが確認。Androidが**前景で別承認**した後、端末KeyStoreの新しいP-256署名をPCが検証。
6. Windowsはこの承認後に限って5〜30秒測り、**1回だけ** `/v3/traffic-finish` の pinned TLS レスポンスに匿名化した集計レポートを入れる。Android本体は16KiBを超える・未知フィールド・集計不一致を拒否。受信・送信合計、平均/秒、ピーク/秒、受信推移をRAMだけに表示。消去・離脱・背景化で破棄し、セッションを再利用しない。

## 安全な境界・未実装

- QR-v3専用フラグ `traffic=1` は `status/file/upload/media` と排他的で、QR単独・過去の確認履歴・TLS pin単独では取得を許可しない。
- SHA-256の範囲分離: `CHAPPY-PC-TRAFFIC-READ-V1\0 || [seconds] || nonce32`。署名は既存Windows DPAPI P-256 / Android KeyStore P-256に依存。旧STATUS/MEDIA署名、誤った端末鍵・計測時間は利用不可。
- QR有効期限最大10分、追加承認最大90秒、QRごとに取得1回。署名不正でも消費・閉鎖し、リプレイ/同時再送を拒否。Androidは操作前/承認時/受信後にWi-FiかつVPN非利用を確認。QRの接続先は選択済みPCと一致必須。
- 直接Wi-Fi上の pinned TLS のみ使用し、**平文HTTPはテスト用localhostのみ**。無認証LANサービス、他機器の盗聴・MITM、常時監視、バックグラウンド接続、JS mini-appへの特権公開、汎用PC操作APIは含まない。
- 本機能のPC通信量レポートは暗号化済みTLS接続内で、署名済みチャレンジに基づく短命認証済み取得であり、04Aの未署名手動JSONとは経路と認証が異なる。全ネットワーク経路を物理的に同一アクセスポイントへ固定する機能、Wi-Fi以外のPC NICを分離した計測、他のLAN機器の利用量は含まれない。

## テスト / 実機ゲート

- `tools/test_pc_traffic_once.py`: 実P-256鍵で本人確認→TRAFFIC別承認→独立署名→一回レスポンス、localhost限定HTTP結合、再送/誤スコープ/拒否/項目漏洩排除。実機ネットワークは利用せず、計測値はモック。
- `docs/netlab-04b-traffic-vectors.json` と `test/pc_traffic_once_test.dart`: Python/Dartの共通SHA-256検証、QRフラグの排他/不正値。
- `test/remote_traffic_report_test.dart`: 04Aからの16KiB/厳格スキーマ・合計検証を共有。
- Quick CI/Windows Companion/Android Debug APK各**最終PR HEAD**の実測結果は統合前に別途記録。
- **物理PC↔Android QAは未実施。** 新しい10秒通信の取得、PCのTRAFFIC承認、端末のWi-Fi変更/VPN切替/背景化、Android各ABIの実機動作は別ゲート。NETLAB-03B 0/15、MEDIA 0/13、R7 0/12など既存の未実機QAも維持する。署名済みStableと公開ミニアプリカタログは別承認なしに変更しない。

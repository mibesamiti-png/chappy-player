# NETLAB-05C — 型番入力なしのルーター候補自動識別（Androidホスト）

**実装区分：ソース/CI・実機は別判定。** 本機能は本人が管理する接続中のWi-Fiから、Androidが持つデフォルトゲートウェイIPv4を取得し、対応するルーターがUPnPで自己申告した場合に限りメーカー/モデル名の**候補**を示すもの。**BUFFALOの実機型番は未提示**、ユーザーの自宅機器を特定した・自動管理APIでログインできたと主張しない。

## 仕様と表示

1. Chappy Playerの **Network Lab → 接続中のルーターを自動識別（型番候補）** を本人が開く。管理するWi-Fiである旨をチェックし、毎回ダイアログで限定探索を明示承認する。勝手なバックグラウンド監視や初回起動時自動探索はない。
2. Androidホストの `ConnectivityManager.activeNetwork` + `getNetworkCapabilities` + `getLinkProperties` を利用。現在のデフォルト経路が**Wi-Fiのみ（VPN/セルラー非該当）**で、そのデフォルトルートのネクストホップがローカルRFC1918 IPv4であることを要求。ゲートウェイIPはOSの観測事実であり、**BUFFALO機体のIPである保証ではない**。
3. 1回のSSDP `M-SEARCH`（`upnp:rootdevice`、239.255.255.250:1900、MX=1）を送信。最大2.4秒・8レスポンス・各2KiB制限で、**送信元IPが正確にOSのゲートウェイと一致した応答だけ**を評価。他のローカル機器の詳細は収集しない。
4. SSDP応答 `LOCATION` がゲートウェイIPv4に**一致**するHTTP URLであれば、パス長/ポート/リダイレクト禁止などを検査し、**同じゲートウェイへ1回だけ公開UPnP機器説明のHTTP GET**（各タイムアウト1.2秒、最大16KiB、Proxy.NO_PROXY、認証やCookie不要）を行う。対象のHTTPは管理ログインではなくルーターが公開する機器の自己紹介XML専用。別IP・DNSホスト・外部/任意サイト・リダイレクトへは接続しない。
5. モデル番号/モデル名/メーカー/フレンドリー名の表示可能文字列（96文字以下）だけを一時表示。証明書やログインによる認証ではなく**UPnP自己申告**なので「型番候補」。応答がない・XMLに識別情報がない場合は **ゲートウェイIPだけ + 型番不明**、推測でBUFFALO型番を作らない。
6. 背景化/画面を閉じる/結果を破棄でRAM上の表示結果を消去。変更されるルーター設定はなく、資格情報・履歴・端末通信内容/通信先・登録されていない他端末の情報は取得しない。Android本体の `dev.chappy.player/network_lab` チャネルに限定し、**.chappyミニアプリJavaScriptへ機能を開放しない**。
7. Android 17（API37）向けの広範囲 `ACCESS_LOCAL_NETWORK` を勝手に追加しない。targetSDK37でOSのサービスピッカーなどが未対応ならfail closed。現在のBluetooth/GPS等の追加権限は不要、既存 `INTERNET`/`ACCESS_NETWORK_STATE`/`CHANGE_WIFI_MULTICAST_STATE` のみ。

## モデル識別の限界

- **BUFFALOがAP/ブリッジ/中継機**ならデフォルトルートに現れるのは別の上流ルーターかもしれない。BUFFALO本体を型番込みで識別できるとは限らない。
- UPnP IGDがOFF、ルーターが応答しない、ゲストWi-Fiやマルチキャスト遮断なら型番は不明。ブランドは勝手に推定しない。
- UPnP XMLは改変・偽装可能な自己申告なので実機ラベルや[BUFFALO公式AirStationアプリ](https://www.buffalo.jp/topics/special/detail/airstation-app.html)で確認する。メーカー側にも「対応商品では検出された商品名を表示」と説明あり（[手順](https://www.buffalo.jp/support/faq/detail/16103.html)）。
- **本機能はBUFFALO機種別APIへの自動ログインや、未登録端末の接続先IP/URL監視を実装するものではない。** 手動端末一覧取込の既存NETLAB-05B、OpenWrt限定NETLAB-05Aは引き続き別画面。登録していない機器の一覧は管理ルーターが実際に提供する情報に依存する。
- SSDP仕様の[UPnP Device Architecture v1.0](https://www.upnp.org/specs/arch/UPnP-arch-DeviceArchitecture-v1.0-20080424.pdf)による検索・自己申告LOCATIONを参照。

## コードと検証

- Android側 `tools/android/NativeRouterIdentity.kt`（生成Android runnerへ`tools/patch_android.py`がコピー）、ホスト`tools/android/MainActivity.kt`の既存network_lab限定メソッド。
- Flutter `lib/core/router_identity_client.dart`、`lib/screens/router_auto_identify_page.dart`、`lib/screens/network_lab_page.dart`。
- `test/router_identity_client_test.dart`、`test/router_auto_identify_widget_test.dart`、`tools/test_router_identity_boundary.py`、Quick CI + Android Debug 3ABI。
- CI合格はソースやエミュレート環境を確認したという意味のみ。**実Android + 家庭用BUFFALOルーターへのWi-Fi UPnP往復、通信制限/ルーターモード別・証拠の正しさ、APK実インストールは未実施として残す**。
- Game R8の8タスク、NETLAB-04A/04B、ASMR、署名Stable/公開カタログ、既存ローカル権限境界は維持する。

# NETLAB-02A — このスマホの通信量モニター（試作版）

**状態:** ソース実装・CI/実機QA確認中。正式署名APK未公開。

## 目的と情報源

Network LabのLANサービス発見に続く通信量モニター。Android標準の
[TrafficStats](https://developer.android.com/reference/android/net/TrafficStats)
で、**このAndroid端末の起動後からの受信・送信バイト数**を読む。
アプリが表示中でユーザーが「計測開始」を押した場合だけ、1秒間隔で
差分を計算して折れ線グラフを表示する。60秒で自動停止。

- **端末全体:** `TrafficStats.getTotalRxBytes/getTotalTxBytes`。
  全アプリ・複数のネットワークインターフェースを含む送受信累積値。
  **Wi-Fiだけ・今つながっているアクセスポイントだけ・発見したLAN端末だけ**
  の通信量ではない。料金請求・VPN計測・ヒストリカル統計の代替ではない。
- **Chappy Player自身の参考値:** `TrafficStats.getUidRxBytes/getUidTxBytes(Process.myUid())`。
  このアプリのUIDのみ。ほかのアプリやユーザーのデータは列挙しない。
  対応していなければ明示的に非表示。
- **時間:** `SystemClock.elapsedRealtime()` でサンプル時間差を計算。
  AndroidのTrafficStatsは起動からの累積値なので、再起動などで減少したら
  履歴をリセット。初回サンプルで速度を架空表示せず「計測待ち」。
- **非対応:** `TrafficStats.UNSUPPORTED`（-1）では0と扱わず、
  非対応と表示して計測終了。リード例外やタイムアウトも停止する。

## 操作

1. Chappy Player Debug → **Chappy Network Lab** → **このスマホの通信量を測定**。
2. 説明ダイアログで計測対象、すべてのネットワーク経路が含まれること、
   60秒終了、保存・外部送信なしを確認し、**60秒間計測する**を押す。
3. 受信/送信のバイト/秒・最大60点のグラフ・計測開始後の受信/送信量を
   リアルタイムで確認。通常のネット通信、動画やWeb閲覧などを自分の端末で
   試して変化を確認する。ほかの端末の通信量を監視する機能ではない。
4. **停止**、画面を閉じる、アプリをバックグラウンドに移す、
   60秒経過のいずれかで終了。再開するには新たに明示操作が必要。
   収集データはRAMにのみ保持し、ページ終了で消える。

## プライバシーと制約

- `MethodChannel('dev.chappy.player/network_lab')` に、foreground Activity
  でのみ応答するホスト専用 `trafficSnapshot` を追加。
  `.chappy` WebViewのJSブリッジには公開しない。
- パケットキャプチャ、ネットワークプロキシ、VPN、独立HTTP接続、
  位置情報・他UID使用統計・保存ファイル・端末識別子は追加しない。
- Androidの追加権限・`PACKAGE_USAGE_STATS`・`ACCESS_LOCAL_NETWORK`・
  `VpnService`は必要ない。端末メーカーやAndroidの集計方法により
  数値が実測パケット/請求データと一致しない可能性をUIにも注記する。
- 既存の `Chappy.network` の公開HTTPS/WSS/TLS/オリジン制約は変更しない。
  LAN機器発見（NETLAB-01）や既存のPCのQR確認とも別機能。

## 検証

- Kotlinネイティブソース・MethodChannelのforeground/JS隔離、
  追加権限なしを `tools/test_network_lab_contract.py` で検査。
- `test/device_traffic_client_test.dart`: 戻り値検証、端末非対応、
  モノトニックな通信量差分、起動カウンターリセット・時間異常を検証。
- `test/device_traffic_page_widget_test.dart`: 明示同意までの無通信、
  毎秒の測定/手動停止、バックグラウンド停止、60秒自動終了を検証。
- Flutter analyze/test、AndroidデバッグAPKビルドのexact-head CI成功が
  マージ条件。**CIだけでXiaomi実機上のカウンター表示を保証しない。**

## 後続課題

- NETLAB-02B：対応機種に限ったWi-Fi/モバイル別のより正確な集計を
  `NetworkStatsManager`と必要なOS許可のレビュー後に設計。
  データ出典/期間/対象/欠測時の表示を明確にし、ユーザー同意なしに
  権限設定へ誘導しない。
- NETLAB-03：安全なPC相互認証、Windows DPAPI/Android KeyStoreでの
  端末登録、PC自身の**明示許可された**読み取り専用ネットワーク統計。
- NETLAB-04以降：管理許可のある機器・ルーターに限定する通信メタデータ。
  通信本文や他端末の秘密情報は扱わない。

本件は開発用Debug APKへ統合する準備であり、正式署名版・Stable/Debug
ミニアプリカタログには新規公開しない。

# NETLAB-04A — 自分のWindows PCの通信量をAndroidで読み込む（ファイル経由）

状態: **ソース実装・CI検証候補。Windows実機とAndroid実機は別ゲート。** Wi-Fiを流れる他の端末のパケット盗聴ではなく、本人が所有/管理する端末自身の送受信量のみを扱う。

## 使い方

1. Windows CompanionのDebug ZIPを自分のPCへ展開し、`Start-ChappyTrafficExport.cmd`を実行。
2. 端末の所有者がPC画面で `TRAFFIC` と入力し、10秒間の送受信カウンターを1秒ごとに計測。終了後、上書きしない新しい `chappy-pc-traffic-YYYYMMDD-HHMMSS.json` を生成。
3. JSONを自分の方法（USBやファイル共有等）でAndroidへコピー。
4. Chappy Player → Network Lab → 「ほかの端末の通信レポートを読み込む」→ 明示同意 → OSのファイル選択からJSONを取り込む。
5. 送受信合計・秒平均・ピーク・受信推移を表示。消去、画面終了、背景化でRAMから破棄。ログ・遠隔送信・保存なし。

Windows CLI: `ChappyCompanion.exe --traffic-export --traffic-seconds 10`。範囲5〜30秒、`--traffic-out`は任意の新規出力先。PC Link/mDNS/ネットワーク待受は起動しない。Windows側は psutil.net_io_counters(pernic=False) で **全インターフェース** を合算する。Wi-Fiだけとは限らずEthernet/VPN/仮想NIC等も含む。

## データの境界

- この方式は他のWi-Fi機器に直接接続しない。通信先IP・サイト名・閲覧履歴・プロセス・機器固有名・通信本文を取得せず、パケット傍受もしない。
- JSONは最大16KiB、`format=chappy.remote-traffic.v1`、`source=windows_pc`、`coverage=all_interfaces`、`interval_ms=1000`。
- `samples`は5〜30件、1件は `rx_bytes` と `tx_bytes` の非負整数のみ。`totals`はサンプル合計と厳密一致しなければ拒否。未知のキーや端末IDを含むレポートは拒否する。
- JSONは **未署名**。PCの値として真正性保証はない。信頼できる本人生成のファイルだけを扱う。
- Android本体のファイル選択だけを使用し `.chappy` JSブリッジや外部ネットワーク権限を追加しない。署名Stable APKや公開カタログを変更しない。

## これで実現するもの／まだ実現しないもの

**今回実装**: 実際にWindows PC上で計測した通信量のファイルを、Androidで読み込んでグラフ表示するデータ経路。
**まだ未実装**: 直接Wi-Fi経由でスマホがPCの値をリアルタイム取得すること、同一Wi-Fi上の全端末を自動列挙すること、ルーター経由の機器別フロー情報、HTTPS本文解読。直接取得にはQR-v3の相互署名/TLSピンとPC側の専用同意、Android側の独立承認を再利用・拡張する。無認証のLAN待受では代替しない。

## テスト区分

- Python自動テスト: mock Windowsカウンター、範囲外・リセット・上書き防止、PC別承認・不正フラグ拒否。
- Flutter自動テスト: スキーマの正常/異常、データの巨大化・未知フィールド・集計不一致、ファイル読込UIの明示承認/キャンセル/背景化破棄。
- CIはLinux/Windows/Android環境のソース品質のみ。実際のWindows 10/11で計測したJSONをAndroidへ転送し表示する実機QAは未実施として別管理。

## 続きの候補

NETLAB-04B: ユーザーが管理するPCとのQR-v3で、端末双方が毎回同意した時だけ短時間の**直接Wi-Fi経由の通信量閲覧**。さらに別途NETLAB-04Cで対応ルーターの管理API/エクスポートを任意接続する。Game R8の予定は保持し、この試作の品質が整うまで優先度を一段後ろにする。
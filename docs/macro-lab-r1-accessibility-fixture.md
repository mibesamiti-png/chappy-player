# Chappy Macro Lab R1 — Android AccessibilityService / 自作画面限定

## 目的と実装
- Native Androidのユーザー補助サービスを、端末所有者が設定画面で明示的にON/OFFできる
- Chappy Playerホーム → 「Chappy Macro Lab（R1実験）」から専用検証画面を開く
- 本人の「固定2ステップを実行」操作で、その画面の検証ボタンをクリック → 固定文字列 Macro Lab R1 OK を入力
- 緊急停止・画面離脱・サービス停止で未処理ステップをキャンセル
- 判定対象は本体のAndroid packageと専用fixture識別子が一致した画面のみ。150ノード探索上限
- イベント内容は一切保存・抽出せず、外部アプリやChatGPTにはアクセスしない
- 任意の外部アプリ操作、自由スクリプト、定期実行、入力内容の記録、スクショ、通信は**未実装**
- .chappyのJSブリッジは拡張せず、プレイヤー本体のFlutterホームからしか起動できない

## Androidサービスの公開範囲
- BIND_ACCESSIBILITY_SERVICEでシステムだけがバインドできる専用サービス
- 実際のイベント通知はAndroidパッケージ名で制限
- canRetrieveWindowContent=true、canPerformGestures=false、isAccessibilityTool=false
- 一般的なアクセシビリティツールであるとは主張しない
- Androidの設定画面でユーザー自身が有効化。アプリから勝手に許可しない
- 安定署名版APKには自動配布しない。Debug専用検証

## 手元のAndroidでの検証手順
1. Debug APKをインストール。既存のStableアプリはアンインストールしない
2. ホーム「Chappy Macro Lab（R1実験）」を開き、接続OFFを確認
3. 「Androidユーザー補助設定を開く」を押し、Chappy Macro Lab R1を自分でONにする
4. 戻って接続ONを確認。「固定2ステップを実行」を押す
5. 自作の検証ボタンの回数が増え、入力欄に Macro Lab R1 OK が表示されるか確認
6. もう一度実行して650ms以内に「緊急停止」を押し、文字が入力されないことを確認
7. 画面を切り替えても操作が継続しないこと、Android設定でOFFにすると実行できないことを確認

Android 13/14は外部インストールAPKの「制限付き設定」によりユーザー補助の有効化が拒否されることがある。解除操作は端末所有者が必要性を判断し、Android標準の設定画面で行う。強制解除や隠れた操作は実装しない。

## 開発・QA状態
- コード: R1実装（PRでレビュー）
- CI: Quick CIのFlutter test・analyze・Androidマニフェスト回帰テストとAPK互換ビルドで確認
- 実機: 未検証（ユーザーの報告待ち）
- Stable署名リリース: 未実施

R2では、まず自作検証画面に限ったユーザー定義の決定論的マクロ編集を検討する。ChatGPTの回答自動取得や送信制限回避のためには使用しない。

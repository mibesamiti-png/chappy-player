# Game Server Lab：実機通信デバッグ手順（2026-11-07）

対象：公開 Chappy Apps → **Debug** の **Chappy Game Server Lab v0.1.1以降**。2026-11-07にXiaomi 11T Pro / Android 14実機から報告された「POSTの送信欄がない」「WSSが3分以上『接続を確認中…』のまま」を受けた操作説明と修正内容。

## 2026-11-07追加：実機通信ログから特定したホスト側の2つの根本原因

Xiaomi 11T ProでGame Server Lab v0.1.1を使った再テストにより、次の通信ログを確認。

- WSS：`WSS接続失敗: Bad state: Proxy or different destination blocked`。これは**相手側サーバーが返した拒否ではなく、Chappy Player自身の接続先安全チェックが投げた例外**。
- HTTPS GET/POST：Cloudflareから `400 The plain HTTP request was sent to HTTPS port` が返った。これはサーバーに到達はしたが、**HTTPSポート443へTLSではない平文HTTPを送ってしまった**症状。GET/POST本文の内容やPostman固有のBANが原因ではない。

**技術的原因**：プレイヤーがDNSで事前検証したIPへ接続するために設定した `HttpClient.connectionFactory` が、HTTPS接続なのに `Socket.startConnect`（平文ソケット）を返していた。DartのHttpClientはカスタムconnectionFactoryの戻り値を自動TLS化しないため、本来は`SecureSocket.startConnect`で暗号化する必要がある（Dart SDKの実装確認済み）。加えて、Dartの`Uri`は`wss`スキームの省略ポートを**0**と扱い、`WebSocket.connect`が`wss`を`https`へ変換するときにその0を引き継ぐ。ホスト側は443以外を拒否するため、正当な`wss://...`接続でも「different destination blocked」が発生していた。

**修正方針**：既存の公開DNS・DNS解決結果IP固定・TLS証明書検証・明示的接続先許可・プライベートIP拒否・リダイレクト拒否を一切緩和せず、カスタム接続を`SecureSocket.startConnect`に置換。`wss`省略ポートはWebSocketライブラリに渡す前に明示的な443へ正規化。8443/9443等の許可済み明示ポートはそのまま維持。誤った404/400を成功扱いしない。テストでTLS/ポートを退行防止する。

**利用条件**：この変更は`Chappy Player`の**信頼済みホスト側Dartコード**なので、公開カタログの`.chappy`だけ更新しても直らない。GitHub Actionsで新しいDebug APKが成功し、ユーザーがインストール後、同じGame Server Lab v0.1.1のGET/POST/WSSを再検証する必要がある。サーバーから実際に200/101が返るかは実機テストまで未検証。正式版APKと公開Stableカタログには影響させない。

参考：[Dart HttpClient.connectionFactory](https://api.dart.dev/dart-io/HttpClient/connectionFactory.html)、[Dart Uri.port](https://api.dart.dev/dart-core/Uri/port.html)。

## 診断結果と修正

- 旧v0.1.0のHTTPS POSTは**上段WSSの `message` テキスト欄を再利用**していた。セクションが離れていたためUIの説明不足。v0.1.1ではHTTPSセクション内に**専用JSON入力欄 `httpsBody`**を設置。
- 旧v0.1.0のWSS接続は失敗した際に例外を通信ログに記録しても、接続状況の「接続を確認中…」を戻さないUI不具合があった。さらに旧プレイヤー本体のJSブリッジはユーザー承認待ちの可能性を考慮して`network.connect`の上限時間を無効にしており、ホスト未応答時に長く固まる可能性があった。
- v0.1.1ではUI側**30秒のWSS確認監視**、失敗理由のログ表示、セッション終了、重複接続操作制限、使い勝手向上のURL入力補助を追加。後続プレイヤー本体にはJSブリッジの**45秒上限**と、接続中止・画面離脱後の遅延接続拒否を追加。
- 現時点で**Postman公開WSSがユーザーの回線で接続できるか否かは未検証**。接続不良の原因がサービス側か、端末のネットワーク/証明書/許可UIかはこの結果だけでは断定できない。修正後は失敗理由を取得できることが重要。
- 安全のため、公開DNSの`https://`/`wss://`・正規TLS証明書・443/8443/9443のみ許可。ローカルIP/ループバック・`http://`/`ws://`・リダイレクトは引き続き禁止。**ネットワークの安全制限は解除しない**。

## まずHTTPSでテスト（WSSサーバー不要）

1. DebugカタログからGame Server Lab **v0.1.1** を明示的に選んでインストール。APK側の変更が未公開でも専用入力欄・UI監視は`.chappy`の更新のみで利用できる。
2. **HTTPS APIテスト**の「GETテストURL」を押す。URLが `https://postman-echo.com/get?test=chappy` になったことを確認し、「GETで取得」を押す。ホストごとの許可ダイアログが出たらURLを確認して許可。正常時は通信ログに `HTTPS GET 200` とリクエスト情報が表示される。
3. 「POSTテストURLとJSON」を押す。URLは `https://postman-echo.com/post`、**HTTPS専用のJSON欄**は `{"type":"ping"}` になる。通信はまだ発生していない。「POSTでJSON送信」を押す。正常時は `HTTPS POST 200` と送ったJSONのエコーを表示。
4. **WSS欄とHTTPS POST欄は別**。GETは本文を送信しない。テスト先は第三者運営なので秘密情報や個人データは送らない。

## 次にWSSをテスト

1. 「リアルタイム接続（WSS）」で「公開テスト用WSSを入力」を押す。URLはPostman公式ドキュメントの `wss://ws.postman-echo.com/raw`。
2. 「サーバーに接続」→接続先の確認ダイアログ（1回目はネイティブのネットワーク能力確認もある）で承認。**何度も連打しない**。
3. 30秒以内に成功なら `接続中` と `接続成功` が表示。上段のWSS送信欄に`{"type":"ping"}`を入力し「メッセージ送信」。エコー `受信:` が戻るか確認。接続後は「切断」を押す。
4. 30秒で応答がない／承認拒否・DNS・TLS・ポート制限の場合、`接続失敗（通信ログを確認）`と具体的なログが表示される。**そのログをコピーして開発に報告**。ユーザー端末でPostman WSSが到達不能な場合でも、プレイヤー自体の不具合とは限らない。
5. バージョン0.1.1以前で「接続を確認中…」が終わらなければ、いったんGame Server Labを閉じて再度開き、最新版のミニアプリに更新する。承認ダイアログが表示中なら拒否してから戻る。

## デバッグ報告に含めてほしいもの

- Mini-Appバージョン、Chappy Player本体のDebug/正式版、Androidバージョン（今回の報告端末はXiaomi 11T Pro / Android 14）。
- 試したURL（**秘密パラメータ・トークンは除外**）、押したボタン、上部の接続状態、**通信ログのエラー行のみ**。
- GET/POST/WSSのどれが成功／失敗か、WSS成功後のecho有無。
- 実機で試していない項目は「未検証」のまま残す。

参照：[Postman Echo API](https://learning.postman.com/docs/developer/echo-api)、[Chappy Player miniapp network policy](../lib/core/miniapp_game_network.dart)。正式署名APKやStableカタログはこの開発で変更しない。

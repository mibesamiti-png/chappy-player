# NETLAB-03B-1 — PC画面QR招待（1回限りのTLS相互確認・試作版）

**状態：ソース試作版。永続ペアリング未実装。PC操作権限なし。Android/Wi-Fi実機QA未実施。**

関連：[Issue #56](https://github.com/mibesamiti-png/chappy-player/issues/56)、[既存NETLAB-03A](network-lab-session-pairing.md)、[Network Labロードマップ](https://app.notion.com/p/410948b74937818f8eea-ca22609052b2)。

## 何ができる？

1. 自分のWindows PCで、明示的に `Start-ChappyPairing.cmd` または `ChappyCompanion.exe --start --pair --qr --minutes 10` を起動。
2. PCが一時的なECDSA TLS証明書を生成。PC画面に**その起動だけで使えるQRコードと証明書SHA-256指紋**を表示。実PCホスト名・既存の署名鍵・PCパスワードをQRに含めない。
3. 同じ管理Wi-FiのAndroid開発版Chappy Playerで、Network Lab → 「PC・ワークステーション」を発見 → `Chappy PC ...` を選択 → **「PCの招待QRをカメラで読み取る」**。
4. QR読み取り内容は **`chappy-pair://v2` 専用スキーム**のみに限定。QRのIPとポートが**事前に選択したNSD発見結果に一致する**場合だけ採用。パラメータ重複・余計なキー・公開IP・不正ポート・不正指紋・期限切れ・遠すぎる期限を拒否。
5. AndroidはQRの**フル64桁証明書指紋をTLSでピン留め**してから、16バイト乱数のnonceとQRから取得した**128bitランダム招待ID**をTLS内で送信。PCは招待ID一致・期限内・未使用を確認してからPC側の確認プロンプトを表示。AndroidとPCの6文字比較コードが同一なら、PC利用者が25秒以内に**YES**と入力。
6. **成功は1回の本人確認だけ**。資格情報の保存、常時接続、PC操作、ファイル取得、通信内容監視は一切実施しない。PC側の有効期限は最大10分で、閉じると無効。

## QR形式

```text
chappy-pair://v2?ip=<RFC1918 IPv4>&port=<1..65535>&fp=<64 lowercase hex>&inv=<32 lowercase hex>&exp=<Unix seconds>
```

- `inv`：セッションごとに暗号論的乱数で生成し、Windows側だけが正解を保持。mDNSの公開TXT属性には入れない。
- `fp`：PCが起動時に生成したTLS証明書のSHA-256指紋。**QRに記載されているだけではPCが正しいとは判断できない**ため、QRは必ず本人が操作中の実PC画面から読み取ること。
- `exp`：UNIX秒。最大10分。Android側とPC側の双方で期限切れを拒否。システム時刻が大きくずれていると失敗する。
- `ip`/`port`：ユーザーがまず選択した発見結果と一致する必要がある。QRだけを読み込んで任意のLAN先へ接続する機能ではない。
- QRのスキームはカスタム転送形式であり、WebサイトへアクセスしたりURLをブラウザで開いたりするものではない。

## 互換性・プライバシー

- `Start-ChappyCompanion.cmd` は従来どおり**存在通知のみ**でPC接続APIなし。
- `ChappyCompanion.exe --start --pair` は従来の「フル指紋を手入力するv1確認」。**QRモードは `--qr` を明示した場合だけv2**を利用。QRモードでv1への自動ダウングレードはしない。
- QRカメラは、利用者が専用ボタンを押したときだけ起動し、画面が閉じたりアプリが非アクティブになると停止。QR文字列は通信解析用として保存せず、`.chappy` JSに公開しない。
- QR内の招待IDは短期の秘密情報。スクリーンショットを共有したり、クラウドへ自動公開したりしない。読み取られてもPC側の明示承認とTLS証明書ピン留めは別途必須。
- Android 17でtargetSdk37以上はLAN権限の適切な機器選択フロー対応まで既存の接続前チェックでfail-closed。
- 既存のゲームサーバー用公開HTTPS/WSSネットワーク通信APIのDNS・TLS制約は一切変更しない。

## テストと未対応

- Python `tools/test_windows_pairing.py`：PCのQR URL生成の固定ベクタ、招待ID一致/拒否/期限/一回限り、TLS証明書の生成とPCコンソール承認、QR描画確認（Windows CIでは依存パッケージを導入）。
- Dart `test/companion_qr_invitation_test.dart`：同一固定ベクタ、期限切れ・余計なキー・重複・公共IP・不正指紋拒否。
- WindowsプレビューはPyInstaller EXE + 確認バッチをCI生成、AndroidはFlutter analyze/testとdebug APKビルドをCI確認。**CI成功だけで実機上のQR読取・ファイアウォール・接続成立は確認できない。**
- Windows本体の実機実行、Androidカメラ権限・QR読取、ネットワーク切替やゲストWi-Fi、実際のQRの読みやすさ、PCコンソール文字コードに関する実機QAは残す。
- **未実装：永続的な相互認証鍵の交換・Android KeyStore/Windows DPAPI・デバイス一覧・解除（Issue #56の残タスク）。** QR招待＝永続ペアリングではない。

## 配布条件

- このPRで正式署名APK・Stable/Debugカタログ・Windows正式署名インストーラは公開しない。
- 正式配布はユーザーの明示的な指示と実際のAndroid/Windows二台のQAを確認してから。

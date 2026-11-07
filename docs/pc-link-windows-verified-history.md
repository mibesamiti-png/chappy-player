# NETLAB-03B-5B — Windows Companionの検証済みスマホ公開鍵・DPAPI履歴

**プレビューコード段階。実機のAndroid↔Windows通信とDPAPI復旧は未検証。正式な恒久ペアリング、接続権限、自動再接続ではない。**

関連：[Android側の確認履歴](pc-link-verified-history.md)・[QR-v3相互認証](pc-link-mutual-qr-v3.md)・[Issue #56](https://github.com/mibesamiti-png/chappy-player/issues/56)。

## ユーザーによる明示操作

1. PC端末キーが無い場合は ChappyCompanion.exe --identity-create を明示実行。既存の端末キーを自動上書きしない。
2. 同一の私有LANで ChappyCompanion.exe --start --pair --qr --identity-pair を手動実行。Android側でQR-v3を読み取り、両端末に表示される確認コードを比較し、PCでYES、Android側で使い捨て署名を明示承認。
3. **双方の署名が検証され、短命HTTPSサービスとmDNS広告が停止した後に限り**、PCコンソールで別の保存確認を表示。ここで大文字 SAVE を入力したときだけ、確認済みスマホの公開鍵SHA-256指紋をローカル履歴に保存。Enter・違う入力・EOFは保存しない。
4. ChappyCompanion.exe --verified-list：保存したスマホの公開指紋と確認日時を表示するだけで通信を開始しない。
5. ChappyCompanion.exe --verified-forget 64桁小文字hex公開鍵指紋：一致したローカル記録を個別削除する前に、さらに大文字 FORGET の入力を必須とする。スマホ側へは通知しない。
6. ChappyCompanion.exe --identity-revoke：従来の REVOKE 確認が通った場合、保存した検証履歴とPCの署名鍵を両方ローカルで削除する。

## 保護・認証上の境界

- 保存先は現行Windowsユーザーの LOCALAPPDATA / ChappyCompanion / verified-phones-v1.dpapi。Windows DPAPI CryptProtectDataで保護された暗号化JSONを排他的な一時ファイル経由でfsyncし、os.replaceで原子的に置換。保存は最大24件、暗号化ファイル上限8KiB。
- 保存内容はschema、保存時のPC端末公開鍵SPKI SHA-256、検証したスマホ公開鍵SHA-256と時刻のみ。PC名、IP、秘密鍵、招待トークン、アクセス権限、ログや接続情報は保存しない。
- 破損・改ざん・重複フィールド・重複指紋・過大サイズ・PC端末ID不一致の場合はエラーとして扱い、空の履歴として黙認しない。端末キーの更新後、旧履歴を自動引き継ぎしない。
- **これは確認履歴のみであり、再利用可能な接続認証情報でもアクセス権限でもない。** 履歴を使ってQR再検証や明示的権限承認を省略しない。
- QR-v1/v2、拒否されたQR-v3、期限切れ、スマホ署名の不一致、キャンセルでは履歴のSAVE候補は生成しない。履歴操作にPCネットワークの起動機能を追加しない。
- Windowsで削除してもAndroid側の記録は別であり、相互失効・同期・常時起動は行わない。Windowsのユーザーアカウントが侵害された場合はDPAPIだけでは保証できない。

## 検証・未完了

- Windows Preview CIに実際のWindows Crypt32/DPAPIの保存・一覧・重複・削除・破損拒否・所有者不一致・クラッシュ時原子的ファイル置換・端末キー失効・CLI安全性を確認するテストを追加。
- 相互署名チャレンジの成功時にだけ記録候補が公開され、拒否・改ざん・期限切れでは公開されないことも検証する。
- Android実機とWindows端末の同一Wi-Fi接続、ファイアウォール、QR、YES/SAVE/FORGET、Windows再起動・ユーザー切替、鍵ローテーション、通信切断・時刻ずれは未検証。
- 正式署名APK、Stable配布、バックグラウンドPCサービス、遠隔操作、ファイル転送、通信量監視は追加しない。

# NETLAB-03B-6B — Windows側の保存済みスマホ公開鍵照合（手動・一時的）

**状態: Windows Companionプレビューのソース実装。Windows↔Androidの物理2台実機による相互認証は未確認。恒久ペアリング・遠隔失効・ファイル転送・PC操作・自動接続ではない。**

関連: [Android側の手動PC照合](pc-link-known-key-comparison.md)・[Windows確認履歴](pc-link-windows-verified-history.md)・[QR-v3相互認証](pc-link-mutual-qr-v3.md)・[Issue #56](https://github.com/mibesamiti-png/chappy-player/issues/56)。

## 手動操作（コンソール）

Windowsの現在のユーザーで過去のQR-v3相互署名が成功し、別途`SAVE`を入力したスマホだけが比較対象になる。端末名/IP/NSD名から自動選択しない。

1. 事前に `ChappyCompanion.exe --identity-status` でPC端末鍵があることを確認し、必要な場合にだけ `--identity-create` を明示実行。Android端末キーも事前に作成しておく。
2. `ChappyCompanion.exe --verified-list` で、Windows DPAPIに保存された以前のスマホの公開鍵SHA-256指紋を確認する。登録がなければ、まず通常の `--start --pair --qr --identity-pair` により1度相互認証し、終わってから表示される`SAVE`をユーザーが明示入力する必要がある。
3. 次回の確認時に、**`ChappyCompanion.exe --start --pair --qr --identity-pair --compare-known-phone`** をコンソールで明示実行。必要なら `--ip 192.168.1.20` も指定。
4. **ネットワークを開始する前に**、過去の検証済みスマホ公開鍵が番号つきで表示される。ユーザーが完全な指紋を見て `SELECT 1` / `SELECT 2` のように入力した場合だけ、その1件を今回の「期待するスマホ公開鍵」として選択する。数字だけの入力、Enter、キャンセル、EOF、履歴空、暗号化履歴の破損などでは**mDNS広告・HTTPS待受を始めない**。
5. 選択後に短命のQR-v3がWindowsコンソールへ表示される。Android側で読み取って通常通り一時認証を開始する。
6. Androidが `/v3/identity-begin` で提示した**署名前の公開鍵指紋**が選択した指紋と異なる場合、PC利用者への`YES`要求やPC秘密鍵の署名を行う**前に拒否**する。この不一致だけでは他の有効なQR請求を消費しない。
7. 指紋が一致した**だけでは本人と認めない**。PCの`YES`承認、PIN留めTLS、Android側の再承認、両方向のP-256署名検証、短命乱数、署名期限が従来通りすべて必要となる。Android側の公開鍵指紋は署名前に誰でも自称できるため、正しい秘密鍵を持つことを確認するまで成功とはしない。

## 鍵の変更、失効と再登録

- 選択した指紋とAndroid側の新しい端末鍵が違う場合、このセッションの比較を解除して無条件に承認することはできない。**コンソールで停止後、新しいQR-v3での本人確認を改めて手動で行う**。
- 正当な機種変更・Android KeyStore鍵更新なのか、別端末による要求なのかは自動判断しない。新端末の本人確認が成功したら、従来通り別途 `SAVE` を入力して新しい公開鍵指紋を履歴へ保存できる。旧履歴を消す場合は `--verified-forget <64桁の指紋>`（`FORGET`が必要）または `--verified-clear`（`CLEAR`が必要）を別に実行する。
- 履歴の存在・指紋一致はログイン権限を作らない。今回の比較は相手への失効要求、過去の確認履歴の自動削除、恒久ペア登録、通信制御、秘密鍵交換、ファイルアクセス、PC操作、自動再接続を一切しない。

## 自動テストと実機未検証

- Windows実DPAPI CI: 2件登録→ユーザーが `SELECT 2` →その指紋だけをQR-v3待受生成へ渡すこと、キャンセル・異常入力・履歴破損・履歴空・オプション不足ではネットワークを起動しないこと、照合選択で暗号文やPC鍵を変更しないことを確認。
- QR-v3状態機械/隔離HTTP: 別の公開鍵指紋はPCのYESや署名前に403で拒否、正しい公開鍵の主張でも署名の偽造は成功しないこと、有効な初回QRの不必要な消費が起こらないことを確認。
- Windows Companion Preview CIでテスト、PyInstallerコンソールEXE生成と無引数起動の無通信動作を確認。Android側通信プロトコル、アプリ本体や正式APK署名は変えない。
- **Windows PC・Android実機を同一Wi-Fiにつないだ連続認証/鍵変更、Windowsアカウント切替、端末再起動、LAN切断、タイムアウト、通知・ファイアウォールの試験は未実施。** 正式配布や権限機能の追加には別途端末QAが必要。

# NETLAB-03B-4B-1 — QR-v3 Windows側のP-256相互認証通信（試作）

**状態：Windowsソース実装・自動テスト対象。AndroidのQR-v3対応・実機ペアリングは未実装。**

[Issue #56](https://github.com/mibesamiti-png/chappy-player/issues/56) / [署名基盤](pc-link-proof-foundation.md) / [オフライン両者承認](pc-link-mutual-proof-session.md)

## 追加内容

- 明示的なコマンド ChappyCompanion.exe --start --pair --qr --identity-qr --minutes 10 だけで有効になる独立したQR-v3プレビュー。従来の --start、--start --pair、--start --pair --qr は従来通り。
- WindowsユーザーDPAPIで保護されたP-256端末鍵が未作成なら **自動生成せずに拒否**。利用者が別途 --identity-create を実行する必要がある。
- QR-v3には従来の ip / port / fp（一時TLS証明書SHA256）/ inv / exp に加えて id（長期PC公開鍵のSPKI SHA256）を含める。fp と id は別物。mDNS名では本人確認しない。
- PC側は短命のプライベートLAN限定HTTPSリスナーを起動。スマホ側はフルTLS証明書指紋を検証する必要がある。v3からv2へフォールバックしない。
- /v3/proof-begin は招待ID、Android公開SPKI、Android発行の32バイトnonceを厳密検証し、PC側に同じ6桁確認コードを表示。PCユーザーが25秒以内に明示的にYESを入力した場合だけ、DPAPI保存済みの秘密鍵で署名したpc_proofとPC発行nonceを返す。
- /v3/proof-finish はAndroidがPC発行nonceに署名したandroid_proofを検証。PCとスマホの署名、双方の承認がそろって初めて一度だけ verified を返す。20秒の送信期限、招待の一回限り使用、改ざん・別鍵・再送・拒否で終了。
- 秘密鍵の送信、長期端末登録、認証トークン、常時接続、PC操作、ファイル転送、通信量監視は追加しない。

## QRとJSON形式

QR:
    chappy-pair://v3?ip=<private IPv4>&port=<1..65535>&fp=<TLS cert SHA256:64 hex>&inv=<16-byte invitation:32 hex>&exp=<Unix seconds>&id=<PC public SPKI SHA256:64 hex>

初回 POST /v3/proof-begin:
    {"protocol":"pair-proof-v3","invitation":"...","phone_nonce":"64 lowercase hex","android_spki":"Base64 DER"}

PC返却:
    {"status":"challenge","protocol":"pair-proof-v3","pc_fingerprint":"...","pc_nonce":"64 hex","expires_at":1234567890,"pc_proof":{"algorithm":"P-256-SHA256","spki":"Base64 DER","signature":"Base64 DER ECDSA"}}

2回目 POST /v3/proof-finish:
    {"protocol":"pair-proof-v3","invitation":"...","phone_approved":true,"android_proof":{"algorithm":"P-256-SHA256","spki":"Base64 DER","signature":"Base64 DER ECDSA"}}

成功:
    {"protocol":"pair-proof-v3","status":"verified"}

クライアントはQR上の id と応答の署名者公開鍵指紋を照合し、さらにQRの fp と実際のTLS証明書を照合しなければならない。応答に含まれるpc_fingerprint単独を信頼しない。

## テストと制約

- tools/test_qr_v3_transport.py：両署名成功、PC/Androidの拒否、不正SPKI/nonce、別セッションの署名流用、再送、QR-v2との分離、HTTPループバックでの二段階確認を検証。テスト用HTTPにはTLSを使わないが、配布時のコード経路は既存のピン留めTLSサーバーだけを使用。
- Windows Companion Preview CIで従来のビルド・実DPAPI・署名と共に検証。正式署名APK、Stableカタログ、既存ユーザーデータは変更しない。
- **現段階のAndroidアプリはQR-v3未対応**。Windowsだけの実装を実際のAndroid相互認証完成とは扱わない。PCとスマホの接続テストも未実施。
- 次の段階：Android QR-v3厳密パーサ、ホスト限定KeyStore署名/検証インターフェース、前面UIでの手動承認、二段階HTTPS送受信、アプリ休止/通信切断・期限切れ検証、実機2台のQA。さらに端末登録/解除/PCアクセス権は別の段階。

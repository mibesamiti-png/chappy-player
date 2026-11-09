# Chappy Player — 最新引き継ぎ / 単一チャット高速開発 v2

更新: 2026-11-09。main R5B統合時点: 1ed1f7d2186148e4ba8fd2dcedb2cf909767ef1b。固定スナップショットのため次回必ず最新HEAD・PR・Actionsを再取得。

## R5A/R5Bの最新確定結果

- R5A Windows→Android: PR #101統合、4MiB/16KiB、PC SEND + Android追加承認、SHA-256、OS Save As。Quick CI #42595700596 とWindows CI #42595700748成功。
- R5B Android→Windows: PR #103統合（1ed1f7d2186148e4ba8fd2dcedb2cf909767ef1b）。本人選択の同名ファイルをPCが事前指定した新規保存先だけに送信。別QR-v3スコープ、PC RECEIVEとAndroid別承認、SHA-256後のno-clobber保存。Quick CI #42599611400 とWindows CI #42599611377成功。
- PC Transfer Lab v0.2.0: 非公開Debug手動QA。R5A/R5B両方向対応。ミニアプリJavaScriptにはPC接続/ファイル権限を与えない。Windows EXEとともにActionsプレビュー成果物を作成。
- Android↔Windows物理2台QAは未実施・0/15。以前のAndroid Debug APK起動確認は今回の転送成功を示さない。
- 公開Chappy Apps Debug 8 / Stable 2、正式署名APK v0.3.0-b11は変更なし。

## 維持する安全境界

QR-v3端末本人確認と証明書ピン、PC/Android双方で別の追加承認。pc.status.read / pc.file.receive / pc.file.uploadは別々の署名スコープ。勝手なPCフォルダ閲覧・パス指定・上書き・PC操作・自動永続接続は禁止。

R5A/Bは各方向1ファイル・最大4MiB・16KiB順序付きチャンク・SHA-256・1回限りの期限付きticket。再開や大容量ファイル転送はまだ未実装。

## 次はR5C（未着手）

大容量の安全なストリーミング、キャンセル/ネットワーク断時の後始末、再承認・ハッシュ検証付き再開、正確な進捗/速度表示、Windows/Androidの障害テスト。具体的な8タスクはSTATE.json参照。

## 最初に読むもの

STATE.json → ROADMAP.md → SINGLE_CHAT_DEVELOPMENT.md → ../pc-link-r5a-file-receive.md → ../pc-link-r5b-upload-once.md → ../pc-link-two-device-qa-matrix.md。次回は最終HEADのQuick/Windows CIを確認してから統合。

Notionは節目の手動更新。GitHubとの常時自動同期はまだない。

# Chappy Recorder CAMREC-16 — ユーザー正式採用記録（2026-11-14）

## 採用判断
2026-11-14、ユーザーが「Recorderのやつは現状デバッグ完了していてUIもいい感じだから、今あるソースを確認して正式採用でいいよ」と直接承認。**現行Debug v0.1.7のソースとUIをそのまま採用**し、機能追加やUIの再設計はしない。

## 対象ソース／検証済み機械的事実
- Chappy Player: https://github.com/mibesamiti-png/chappy-player
- 参照main: `7b90c485a5f49634ce5847bdee388072b2617dbf`
- ミニアプリ: `sample_apps/video_recorder/index.html`、blob `d9ea3f7d25b5d2b85350f524450b18b3ec4598c2`
- Recorder機能PR: https://github.com/mibesamiti-png/chappy-player/pull/142 （main統合済み）
- Quick CI 76/76: https://github.com/mibesamiti-png/chappy-player/actions/runs/42876978962
- Android 3 ABI 17/17: https://github.com/mibesamiti-png/chappy-player/actions/runs/42876978926
- Debug v0.1.7のカタログPR: https://github.com/mibesamiti-png/chappy-apps/pull/11
- DebugパッケージSHA-256: `5a18b751848a09fbfc5cbadda7d7ff795b6b2635616d8f621f97e30c57a9440d`

## QA情報の区別
- **本人の報告**: デバッグ作業は完了、UIの見た目も承認、現行ソース正式採用可。
- **独立に確かめた範囲**: 既存CIとソース構造、公開カタログの整合性。ユーザーの実機操作について項目別の結果・機種・ログはこの報告に含まれていない。
- **記録方針**: 端末QAを「未実施」と断定せず「ユーザー報告でデバッグ完了、個別ケース未記録」とする。各ケースのPASS数やOS側挙動は推測で補完しない。
- **維持する安全要件**: Androidのカメラ/マイク許可と使用インジケータ、録画中通知・停止操作、本人による録画開始、保存データの保護。

## 配布の現状と残るゲート
- 2026-11-14 Chappy Appsカタログ: Debug `0.1.7`、Stable `0.1.0`。Stableにはまだ反映していない。
- 現行公開署名本体は `v0.3.0-b11`（2026-11-06）。新しいCameraX画面OFF録画・スマート録画/通知連動はその後のソースにあり、**現行署名本体との機能互換を推定しない**。
- Stableミニアプリだけ先に公開しない。対応する署名APKの新ビルドを検証し、固定署名・ABI別versionCode・更新フィード・既存データ保持を満たしたうえで、**署名APK公開はユーザーの別途明示指示**を受ける。
- ミニアプリStable化時はimmutableな新パッケージと対応するカタログSHA-256/sizeBytesをセットでPR化し、公開カタログのCIを通す。現行UIの使用感は維持し、Debug表記や「Debug本体を更新」案内だけはチャンネル整合の確認対象とする。

**承認範囲は現行Recorderの機能・UIを正式採用すること。配布完了・署名APK公開・個別実機テストの全項目合格とは別。**

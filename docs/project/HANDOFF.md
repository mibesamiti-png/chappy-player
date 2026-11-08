# Chappy Player — 最初に読む引き継ぎ入口

> 更新日: 2026-11-08 | 単一チャット高速開発方式 v2
> 確認したmain SHA: `ad95401f86362c760139990241a7546984c809f6`（**この時点のスナップショット**、次回必ず再取得）

## 最初の60秒でやること

1. GitHub main最新HEAD、Open PR、最終HEADのCIを再取得。本文のSHAが現HEADだとは決めつけない。
2. [STATE.json](STATE.json) → [ROADMAP.md](ROADMAP.md) → [SINGLE_CHAT_DEVELOPMENT.md](SINGLE_CHAT_DEVELOPMENT.md) の順に読む。
3. PC Linkの実装を始めるなら [R4Bオフライン契約](../pc-link-r4b-session-preview.md)、[QR-v3](../pc-link-mutual-qr-v3.md)、[15項目実機QA](../pc-link-two-device-qa-matrix.md)、対象のWindows/Dartコードと回帰テストを読む。
4. **次の未着手バッチはPC Link R4C**。R4BはソースとCIまで完了。実Windows↔Android通信・状態取得はまだ出来たと扱わない。
5. 1チャットで5〜10関連タスク、事前検証→一括コミット→1PR→最終HEADのQuick CI＋Windows CI→統合→状態更新。競合ブランチや他者の未完了PRを再マージしない。

## 最新の確定証拠

| 項目 | 状態 | 証拠 |
| --- | --- | --- |
| PC Link R4B | Python/Dartオフラインセッション、独立同意・失効・127.0.0.1模擬通信 **ソース統合済み** | [PR #97](https://github.com/mibesamiti-png/chappy-player/pull/97)、merge `ad95401f86362c760139990241a7546984c809f6` |
| R4B Quick CI | **成功**、Flutter analyze・テスト・Python/Dartループバック | [Run #42468375810](https://github.com/mibesamiti-png/chappy-player/actions/runs/42468375810) |
| R4B Windows CI | **成功**、Python契約/安全テスト・Windows EXEビルド | [Run #42468375793](https://github.com/mibesamiti-png/chappy-player/actions/runs/42468375793) |
| R4A前段 | QR-v3起動スクリプト、--doctorを実装 | [PR #95](https://github.com/mibesamiti-png/chappy-player/pull/95) |
| Android Debug起動 | ユーザーが起動成功を報告 | 2026-11-08会話。R4BやPC実機QAの成功ではない |
| PC Link Windows↔Android QA | **0/15 未実施** | [2台QA](../pc-link-two-device-qa-matrix.md) |
| Chappy Apps | Debug 8・Stable 2 | [catalog.json](https://github.com/mibesamiti-png/chappy-apps/blob/main/catalog.json) |
| 正式署名APK | v0.3.0-b11、R4Bは非公開 | [Releases](https://github.com/mibesamiti-png/chappy-player-updates/releases/tag/v0.3.0-b11) |

## R4Cの主要対象コード

- Windows: `examples/windows_companion/identity_pairing_v3.py`, `pairing_server.py`, `offline_session_preview.py`, `mutual_proof_session.py`
- Android: `lib/core/companion_identity_exchange.dart`, `pc_link_preview_session.dart`, `lib/screens/companion_pairing_page.dart`
- 契約: `docs/pc-link-session-preview-v1.json`（R4Bテスト専用、**そのまま本番認可として使わない**）
- テスト: `tools/test_pc_link_r4b.py`, `test/pc_link_preview_session_test.dart`, `tools/test_pc_link_r4b_boundary.py`

## 次回の報告に必須

最新main／開始との差分、バッチID・実装済み/残り、PR・最終HEAD・CI URL、Debug APK/実機/Stableの別判定、次に触るファイル。状態の正本はコードとGitHubのPR/CI。Notionは人間向けの節目更新で、常時同期は未実装。

**セキュリティ**: 署名の検証成功＝PC操作許可ではない。R4Bで使ったテスト用の真偽値を本番認証に転用しない。ユーザーの鍵・招待・保存データをGitHubに置かない。

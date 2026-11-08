# Chappy Player — 最初に読む引き継ぎ入口

> 最終整理: 2026-11-08 | 単一チャット高速開発方式 v2

## 60秒で再開する手順

1. **GitHub mainのHEADを必ず再取得**。ここに書かれた `0171d30109db0bed2d1e299bc458fda67c82b228` は2026-11-08のR4A完了時点の基準で、恒久的な最新HEADではない。
2. `docs/project/STATE.json` の現在の焦点、`docs/project/ROADMAP.md` の次バッチ、`docs/project/SINGLE_CHAT_DEVELOPMENT.md` の手順を読む。
3. 最新PR（open/merged）、その **最終HEAD** に結びつくCI（Quick CI、Windows変更時はWindows Companion Preview）、現実の公開版と成果物を確認。STATEやNotionが古ければコード/CIを優先して直す。
4. 進行中ブランチや別チャットの作業がないか確認し、未完了の同一タスクを重複実装しない。既存の開発順は、承認済みの最新方針があればそれに従う。
5. **次：PC Link R4B**。詳細と8つの候補は `STATE.json` と `ROADMAP.md`。実機検証待ちを理由に、オフラインで作れる安全な状態機械/型・契約テストは止めない。

## 直近の確定記録

| 項目 | 判定 | 証拠 |
| --- | --- | --- |
| PC Link R4A | コード統合済み | [PR #95](https://github.com/mibesamiti-png/chappy-player/pull/95)、merge `0171d30109db0bed2d1e299bc458fda67c82b228` |
| Quick CI | PR最終HEAD成功 | [Run #42443650137](https://github.com/mibesamiti-png/chappy-player/actions/runs/42443650137) |
| Windows Companion CI | PR最終HEAD成功、EXE Artifact生成 | [Run #42443650188](https://github.com/mibesamiti-png/chappy-player/actions/runs/42443650188) |
| Android Debug APK | 起動クラッシュ修正版で起動したとユーザーが報告 | 2026-11-08会話報告。R4Aソースを含む新APKの実機検証ではない |
| PC Link Android↔Windows QA | **0/15、未実施** | [QA表](../pc-link-two-device-qa-matrix.md) |
| 公開ミニアプリ | Debug 8 / Stable 2 | [chappy-apps catalog](https://github.com/mibesamiti-png/chappy-apps/blob/main/catalog.json) |
| 最新正式版の確認 | v0.3.0-b11 （R4Aは未公開） | [Releases](https://github.com/mibesamiti-png/chappy-player-updates/releases/tag/v0.3.0-b11) |

## 今すぐ再開する場合に読む主要ファイル

- `examples/windows_companion/identity_pairing_v3.py`, `pairing_server.py`, `companion.py` — Windowsワンタイム相互認証
- `lib/core/companion_identity_exchange.dart`, `lib/screens/companion_pairing_page.dart` — Androidホストの認証と承認
- `docs/pc-link-mutual-qr-v3.md`, `docs/pc-link-r4-offline-readiness.md` — 安全上の前提
- `tools/test_identity_pairing_v3.py`, `test/companion_qr_lifecycle_test.dart` — 既存回帰
- `docs/project/STATE.json` — 機械的な現在地・次タスク

## 引き継ぎの報告フォーマット

- 最新main SHA（取得時刻）／開始時と比較した差分
- 今回のバッチID、実装タスク数と未実装タスク
- PR番号・最終HEAD・CI実行URL・成功／失敗／未実行
- 実機のPASS／FAIL／未実施（コードやCIの合格と混ぜない）
- Debug APK生成／公開カタログ更新／Stable公開を別々に記載
- 次に触るファイル、リスク、次の5〜10タスク

**注意:** このファイルとNotionは固定スナップショット。GitHubとの自動同期を実装したとは主張しない。

# Chappy Player — 最新開発引き継ぎ（単一チャット高速開発 v2）

> 最終更新: 2026-11-09 / GitHub main確認時点SHA: `cc4a692b0d4c3e687e2344f399ff7111811f9e34`
> **これはスナップショット。次回必ず最新main HEAD・PR・CIを再取得すること。**

## 60秒で再開する

1. 最新main HEAD、open PR、最終HEADのActionsを再取得し、重複・競合を確認。
2. [STATE.json](STATE.json) → [ROADMAP.md](ROADMAP.md) → [SINGLE_CHAT_DEVELOPMENT.md](SINGLE_CHAT_DEVELOPMENT.md) を読む。
3. 今回のR4Cについては [R4C read-only status設計](../pc-link-r4c-status-once.md)、[QR-v3本人確認](../pc-link-mutual-qr-v3.md)、[実機QA 15項目](../pc-link-two-device-qa-matrix.md) を読む。
4. **次はPC Link R5（未着手）**。実機の本格デバッグ前に作れる安全なファイル転送の骨組み、ホストUIとPC Transfer Labを実装する。すべての権限・本人の選択を明示し、R4Cのstatus権限をファイルに流用しない。
5. 1チャット内で関連5〜10タスク、可能なら一括コミット・1PR。Quick CI / Windows CIの最終HEAD成功を確認後、mainへ統合。Notionは節目で手動更新。

## 最近の確定成果

| 項目 | コード / CI | 実機 / 配布 |
| --- | --- | --- |
| **R4C read-only PC status** | [PR #99](https://github.com/mibesamiti-png/chappy-player/pull/99)統合、main `cc4a692b0d4c3e687e2344f399ff7111811f9e34` | **Android↔Windows QA未実施** |
| R4C Quick CI | [#42587043221](https://github.com/mibesamiti-png/chappy-player/actions/runs/42587043221) **成功** | Dart/Flutterおよび安全性テスト |
| R4C Windows Preview CI | [#42587042801](https://github.com/mibesamiti-png/chappy-player/actions/runs/42587042801) **成功** | Windows EXEプレビューArtifact生成。実PC利用確認ではない |
| R4B前段 | [PR #97](https://github.com/mibesamiti-png/chappy-player/pull/97) オフラインstate+127.0.0.1模擬連携 | R4Bは本番接続には未接続のテスト専用 |
| PC Link物理2台テスト | **0/15・未実施** | [15項目](../pc-link-two-device-qa-matrix.md) |
| Android Debug APK | ユーザーの以前の起動成功報告あり | R4Cの変更を含むDebug APKを実機検証したわけではない |
| Chappy Apps | Debug 8 / Stable 2（今回変更なし） | [catalog](https://github.com/mibesamiti-png/chappy-apps/blob/main/catalog.json) |
| 正式署名APK | v0.3.0-b11（今回変更なし） | [Releases](https://github.com/mibesamiti-png/chappy-player-updates/releases/tag/v0.3.0-b11) |

## R4Cのセキュリティ境界（絶対維持）

- Android KeyStore/Windows DPAPI、QR-v3本人確認、QRで固定したTLS証明書。
- `--status-once` はWindowsの明示オプトイン。PC側で通常YESのほか、別のSTATUS承認が必要。
- Androidの別承認とドメイン分離した新しいP-256証明がそろってから、PCの論理CPU/RAM/uptimeだけを1回取得。
- 結果はホスト画面内だけ。Hostname/IP/プロセス/ファイル/通信内容/PC操作は取得しない。
- 1回限り・QR期限と認証後90秒上限。秘密や権限をJSへ公開しない。
- これは永続セッション・自動再接続・PCファイル転送の認可ではない。R5では独立した明示権限・安全な経路を作る。
- CI成功を実機PASSや正式公開と混同しない。

## R5再開対象

- Windows `examples/windows_companion/status_once.py`, `pairing_server.py`, `pc_status_metrics.py`（権限境界の参考、ファイルアクセスに転用不可）。
- Android `lib/core/companion_identity_exchange.dart`, `pc_status_once.dart`, `lib/screens/companion_pairing_page.dart`（明示承認とホスト隔離の参考）。
- R4Cテスト `tools/test_pc_status_once.py`, `tools/test_pc_status_boundary.py`, `test/pc_status_once_test.dart`、QRテスト。
- 安全な独立転送を新しい機能スコープで設計すること。Windowsの一般的な任意パス取得・リモートシェルを追加しない。

**Notionは人間向けの節目更新であり、GitHubとの常時自動同期は未実装。**

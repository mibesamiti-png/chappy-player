# Chappy QA Checklist v0.1.0（公開Debug専用）

## 目的

最新の [Network Lab実機デバッグ全9項目](../../docs/qa/NETLAB_DEBUG_2026-11-10.md) を、**AndroidのChappy Player上で開く独立したミニアプリ**として表示する。手動チェック結果を保存して再訪時に再開でき、短い結果レポートをコピーできる。QA-01～QA-09はすべて「未実施」から開始し、**Flutter CI/ビルド成功を自動的に実機PASSへ変換しない**。

## 操作

1. Chappy Player → **Chappy Apps（公開ライブラリ）→ Debug 開発版** →「Chappy QA Checklist」をユーザーが選択して追加。
2. ホームから追加したミニアプリを起動。
3. 本体の「端末セルフチェック」「Network Lab」へ移動して1件ずつ実機で操作し、リストの判定を **成功／失敗／保留／未実施**から選択。
4. 「レポートをコピー」または手動選択。共有前に個人情報を確認。
5. 「全項目リセット」は確認後に判定と画面内メモを消す。

## データ・権限・公開方針

- **ミニアプリ権限は `[]`**。native bridge、通信機能、カメラ・マイク、ローカルファイル読取、ルーターへのアクセスを追加しない。外部の計測結果を捏造しない。
- `localStorage` へ保存されるのは `QA-01`～`QA-09` の**4値の判定だけ**。メモ・入力したRun ID・Androidバージョン・コピー用レポートは**画面を閉じると消える**。可能ならアプリを閉じる前にレポートをコピー。背景化時の保存を別途実装していない。
- 個人の実IP/MAC、キャプチャ、パスワード、認証トークン等は入力しないよう注意喚起。**このDebugミニアプリは公開リポジトリにも配布可能な、人工的な検証項目しか持たない**。
- チェックリストのQA-07～08に用いる合成PCAPは別途取得し、mini-appが勝手に読み込まない。mini-appとNetwork Labは独立。
- 公開検証済みの新しいミニアプリは、原則 **Chappy Apps Debugチャンネルに先行登録**し、**本人の明示的追加操作**を必要とする。安定版や本体への自動追加はしない。**非公開・未レビュー・機密データを含む実験アプリ、権限の強い検証ツールは自動公開しない**。

## 検証・配布

- `node tools/test_debug_checklist.js`
- `python3 tools/pack_html_chappy.py --source sample_apps/debug_checklist --id local.chappy.qa_checklist --name "Chappy QA Checklist" --version 0.1.0 --output build/chappy-qa-checklist-v0.1.0.chappy`
- Quick CIでは、Nodeテストとパッケージ形式/空権限を確認し、Debug専用成果物としてアップロード。
- Chappy Apps別公開リポジトリの `debug/` に実バイトの`.chappy`を登録し、カタログに実測SHA-256/サイズを記載。公開Debug配布はStableとは完全分離する。
- 実機WebViewでの見た目、localStorage持続・コピーの挙動は**ユーザーテスト未実施**であり、静的テスト/CIとは区別する。

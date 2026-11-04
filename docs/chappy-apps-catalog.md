# Chappy Apps 公開カタログ (Stable / Debug)

## 構成

AndroidのChappy Player本体とは別に、`.chappy` ミニアプリだけを配布するための**公開GitHubリポジトリ** `mibesamiti-png/chappy-apps` を想定。ソースを置く非公開 `chappy-player` と、正式署名APK専用 `chappy-player-updates` はそのまま分離する。

**注意：2026-11-04時点で `chappy-apps` は未作成。** 新規公開リポジトリの作成はリポジトリ所有者がGitHubで行う。作成前はプレイヤーの「Chappy Apps」画面に取得エラーが出る。空の `catalog.json` を最初に置けば接続テストできる。

```text
chappy-apps/ (Public, main)
├── catalog.json
├── stable/
│   ├── memo.chappy
│   └── asmr-sound-lab.chappy
└── debug/
    ├── memo-next.chappy
    └── asmr-sound-lab-test.chappy
```

**Publicのdebugも全世界に公開される。** 非公開のプロトタイプ、個人データ、APIキーなどはアップロードしない。開発中のソースは既存の非公開GitHubリポジトリに保持する。

## カタログ形式

```json
{
  "schemaVersion": 1,
  "entries": [
    {
      "id": "local.chappy.memo",
      "name": "メモ帳",
      "description": "オフライン保存できるメモ帳",
      "version": "1.0.0",
      "channel": "stable",
      "url": "https://raw.githubusercontent.com/mibesamiti-png/chappy-apps/main/stable/memo.chappy",
      "sha256": "（実際のAPKではなく.chappyの64文字SHA-256）",
      "sizeBytes": 12345
    }
  ]
}
```

上は形式例。実際の `sha256` / `sizeBytes` にはファイルから算出した正確な値が必要。最初の動作確認は **`{"schemaVersion":1,"entries":[]}`** を使ってよい。存在しないファイルや架空のSHA-256を登録しない。

- カタログURL: `https://raw.githubusercontent.com/mibesamiti-png/chappy-apps/main/catalog.json`
- `channel`: `stable` または `debug`
- `id`/`version`: ZIP内 `manifest.json` と完全一致させる
- 各 `.chappy` は12MiB以下で、既存のZIP安全性チェックに通る構造
- カタログは最大100件・64KiB。アプリ本体は12MiBまで
- プレイヤーは HTTPS公開先を固定し、サイズ＋SHA-256＋ZIP構造＋アプリID＋バージョンを確認し、追加前にユーザーへ確認する
- 同じIDで別チャンネルのファイルを配布できるが、プレイヤー上では同じアプリに上書きされる。**保存データのバックアップを推奨**

## 登録・更新の運用

1. HTML / CSS / JavaScriptなどをZIP形式の`.chappy`へパッケージ化する。
2. 非公開ソースのまま動作確認し、公開して問題ない完成ファイルだけを `stable/` または `debug/`へ置く。
3. `catalog.json` の対応する `id` / `version` / `url` / `sha256` / `sizeBytes`を更新する。
4. Chappy Playerホーム →「Chappy Apps 公開ライブラリ」→ Stable / Debug を切り替え、「更新」を押す。
5. プレイヤー本体はAPK化する必要なし。ミニアプリのダウンロード／登録時だけ、端末で内容を確認する。

初期カタログは `catalog_template/catalog.json` に用意。後続開発でHTMLを.chappyへ梱包し、Stable/Debugフォルダからカタログを自動生成するCLIを追加する。

## 権限とセキュリティ

GitHubのアクセストークン・署名鍵はプレイヤー内に一切埋め込まない。カタログとZIPはどちらもユーザーの確認なしに実行しない。GitHub公開リポジトリに対するSHA-256は輸送時の破損やカタログとの食い違いの検証であり、**別の開発者のコードが絶対安全であるという証明ではない**。今は信頼する自作品を対象とする。

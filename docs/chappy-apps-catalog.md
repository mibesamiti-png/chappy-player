# Chappy Apps 公開カタログ (Stable / Debug)

## 2026-11-10：Chappy Recorder スマート録画 v0.1.4（Debug専用）

Chappy Player [実装PR #136](https://github.com/mibesamiti-png/chappy-player/pull/136) でCAMREC-13-R1を実装、[Quick CI 74/74](https://github.com/mibesamiti-png/chappy-player/actions/runs/42721111102)、[Android 3ABIビルド17/17](https://github.com/mibesamiti-png/chappy-player/actions/runs/42721110750)成功。公開 Chappy Apps [PR #8](https://github.com/mibesamiti-png/chappy-apps/pull/8)で `local.chappy.recorder` の**Debug**を `0.1.4` に更新、[カタログ検証7/7](https://github.com/mibesamiti-png/chappy-apps/actions/runs/42722599197)。公開Stableは変更なし。**Stable 2・Debug 9**のまま。

配布実バイトは `debug/chappy-recorder-motion-v0.1.4.chappy`、SHA-256 `b6ea14d27fda2140c96dbd511075dc6e5f097b0c5a00b12e98af45285b1c0324`、25,850 bytes。宣言権限は従来の`camera`+`microphone`。Android本体も新しくしないとスマートモードは使えない。旧本体では通常録画だけを選択できる。Android実機で録画が成功したと断言するものではない。本人が Chappy Apps → Debug → 更新 → Chappy Recorder を選択追加。既存の保存データ・Stableのバックアップに注意。


## 2026-11-10：実機デバッグ用チェックリスト追加

新規 `Chappy QA Checklist v0.1.0`（`local.chappy.qa_checklist`）を **公開Debug** に登録。現時点で**Stable 2本・Debug 9本**（従来8＋新規1）。ソース `sample_apps/debug_checklist/`、[実装PR #133](https://github.com/mibesamiti-png/chappy-player/pull/133)、[公開登録PR #7](https://github.com/mibesamiti-png/chappy-apps/pull/7)。実機の操作手順 `docs/qa/NETLAB_DEBUG_2026-11-10.md` の9件を手動判定し、レポートをコピーできる。追加権限 `[]`、判定のみ端末内に保存、メモや通信内容を外部に送らない。

**今後追加するミニアプリ**：機密・実ユーザーのデータ・認証情報を含まず、コードとパッケージをレビューしてテスト合格したものは、ユーザーが選んで追加できるDebugライブラリへ先行登録する。既存の非公開QAプレビューや公開承認がない試作、強い権限のある機能を自動公開しない。Stable公開は別判断。本体Debug APKへの強制同梱/自動インストールは行わない。



## 構成

AndroidのChappy Player本体とは別に、`.chappy` ミニアプリだけを配布するための**公開GitHubリポジトリ** `mibesamiti-png/chappy-apps` を想定。ソースを置く非公開 `chappy-player` と、正式署名APK専用 `chappy-player-updates` はそのまま分離する。

**現状（2026-11-07）：公開リポジトリ [chappy-apps](https://github.com/mibesamiti-png/chappy-apps) は作成済み。** `main/catalog.json` にはStable 2種類（ASMR Sound Lab / Chappy Recorder）とDebug 8種類の自作ミニアプリが掲載されている。アプリ内では **Chappy Apps 公開ライブラリ → Debug → 更新** から任意のミニアプリを選んで導入できる。プレイヤー本体のDebug APKに全部を自動インストールする仕様ではない。

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

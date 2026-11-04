# HTML / JavaScriptを .chappy へ移植する

ASMR Sound Labなど、HTML/CSS/JavaScriptで作ったアプリをオフラインの `.chappy` ZIPにまとめる道具を追加した。**実際のASMRソースの移植テストはこれから**。

## 作業フォルダ
```text
asmr-html/
  index.html
  app.js
  style.css
  assets/local-sound.wav
```

## 変換
```bash
python3 tools/pack_html_chappy.py --source ./asmr-html --id local.chappy.asmr --name "ASMR Sound Lab" --version 0.1.0 --output ./asmr-sound-lab.chappy
```

このコマンドは元のHTMLを変更せず `manifest.json` を生成してZIPに同梱する。シンボリックリンク、危険なパス、過大ファイルを拒否する。既存出力の自動上書きはしない。

## 公開Stable/Debugの一覧生成
公開用の `chappy-apps/stable` または `chappy-apps/debug` に `.chappy` を配置した後、
```bash
python3 tools/build_chappy_catalog.py --root ./chappy-apps --output ./chappy-apps/catalog.json
```
を実行する。実ファイルのSHA-256・容量・マニフェストから登録情報を生成する。公開前に音声素材の権利や個人情報を確認する。

## ASMR移植の注意
Web Audioやタッチ操作は移植しやすい可能性がある一方、WebM録音、ファイル書き出し、AudioWorklet、外部CDN、オンライン音声素材は個別に確認が必要。保存データは `Chappy.storage` への移行を推奨。

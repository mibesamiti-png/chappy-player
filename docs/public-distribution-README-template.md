# Chappy Player — APK配布

ここは **Chappy Player のAndroid用APK配布専用リポジトリ**です。

この公開リポジトリに置くものは、リリース済みAPK、`update.json`、
リリースノートだけです。署名鍵、トークン、
メモ帳やバックアップなどの個人データは置きません。

## APKをインストールする

[Releases](https://github.com/mibesamiti-png/chappy-player-updates/releases)
から端末のCPUに合うAPKを選んでください。

- **ARM64 / arm64-v8a**: ほとんどの最近のAndroidスマートフォン
- ARM32 / armeabi-v7a: 32ビットARM端末
- x86_64: 対応するエミュレーターやIntel/AMDベース端末

通常の更新ではChappy Playerアプリ内の更新センターを使うと、
端末に適したAPKを自動選択します。Androidのインストール確認は必要です。

## 更新フィード

`update.json`にはバージョン、CPU別APKのURL、サイズ、SHA-256が含まれます。
まだ初回のリリースが無い間は、このファイルは存在しません。

## 注意

個人制作のテスト段階のアプリです。重要なデータはバックアップしてください。
初回の固定署名版と従来のデバッグ版は署名が異なる場合があり、
その場合は上書きインストールできません。

開発用ソースコードは [chappy-player](https://github.com/mibesamiti-png/chappy-player) で公開しています。正式署名鍵や配布トークンは公開していません。

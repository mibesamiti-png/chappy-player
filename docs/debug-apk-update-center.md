# Chappy Player Debug — dedicated in-app APK update channel

Status: Code and workflow proposal. The first fixed-key Debug APK has **not** been published; device QA is required.

## Two APK streams

- Production Android package: dev.chappy.chappy_player. Its current public update.json and non-prerelease history are unchanged.
- Debug Android package: dev.chappy.chappy_player.debug. It will read the separate public debug-update.json feed and Debug prerelease history.
- The installed Android package ID selects the update channel. A mini-app cannot change it.
- The app uses HTTPS, SHA-256, exact APK byte count, native signer/package/versionCode preflight and Android's standard user-confirmed installer.
- The Chappy Apps Debug library distributes .chappy mini-apps, not Android host APKs.

## One-time fixed Debug signature

Existing CI debug builds use an ephemeral runner debug keystore, so their signatures may differ. **This makes ordinary updates between old Debug APK builds unreliable.** Use a NEW dedicated fixed Debug keystore, separate from the formal production signing key. The first switch may require uninstalling only the previous Debug app. Before doing so, back up data. Uninstalling erases Debug-only mini-app data and private videos; private MP4 export is not yet implemented. Do not uninstall if a private video must be preserved.

Create a new Debug-only keystore in a private location using a JDK, for example:

    keytool -genkeypair -keystore chappy-debug.jks -alias chappydebug -keyalg RSA -keysize 3072 -validity 36500 -storetype PKCS12

In the source repository GitHub Settings -> Secrets and variables -> Actions, register repository Secrets:
- CHAPPY_DEBUG_KEYSTORE_B64 (complete keystore file encoded as base64, one line)
- CHAPPY_DEBUG_STORE_PASSWORD
- CHAPPY_DEBUG_KEY_PASSWORD
- CHAPPY_DEBUG_KEY_ALIAS

Add Actions Variable CHAPPY_DEBUG_CERT_SHA256: the 64-character SHA-256 of the DER certificate exported by keytool. Export the certificate using:

    keytool -exportcert -keystore chappy-debug.jks -alias chappydebug -file chappy-debug-cert.der
    certutil -hashfile chappy-debug-cert.der SHA256

Do not send keystores, passwords or private signing materials in a chat or public repo. Back up the Debug keystore offline. The existing CHAPPY_PUBLISH_TOKEN must be scoped to the public distribution repository.

## Publishing a Debug APK

After the PR is tested and merged, run the manual GitHub Actions workflow named **Publish Fixed-Signature Debug APK** from main with version (e.g. 0.2.5) and public release notes.

It validates secrets and the pinned certificate, runs Flutter tests and a Debug Android APK build, checks the real package ID, versionCode and signing certificate, then publishes a GitHub prerelease carrying ChappyPlayerDebug.apk. Finally it writes **only** debug-update.json in the public updates repo. The formal release feed update.json and formal release keys are not touched.

The first stable-key Debug release may need a one-time reinstall. Every subsequent fixed-key Debug release with a greater versionCode supports native Android in-place updates.

On the phone: Chappy Player Debug -> プレイヤー本体の更新 -> 最新版を確認 -> choose a version -> ダウンロードして更新 -> approve Android's installer. A wrong package, signer, digest, size, or older versionCode is rejected. No unattended installation is performed.

## QA checklist

Run CI on the exact feature PR head; perform a manual publish only after it passes. Confirm that Android 14 can download, verify and install a Debug APK from within the Debug update center while keeping the signed production Chappy Player unchanged. Verify an installed fixed-key Debug app preserves its private data after the NEXT fixed-key update. Negative cases: wrong signer, changed Android package, stale feed, downgrade, truncated download, and unavailable GitHub API.

GitHub Actions artifact downloads are not used for this feature: they can expire and may require GitHub authentication.
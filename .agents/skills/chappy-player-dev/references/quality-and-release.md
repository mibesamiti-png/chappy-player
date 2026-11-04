# Quality gates and release checks

This checklist complements the workflow in ../SKILL.md. Use only the steps relevant to the change. Actual repository code and tests prevail if this reference becomes stale.

## Code and test sequence

For a local environment with Flutter installed (do not regenerate an existing runner casually):

```sh
flutter pub get
flutter analyze
flutter test
node tools/test_bootstrap.js
python3 tools/test_verify_signed_release.py
python3 tools/test_chappy_package_tools.py
python3 tools/test_update_feed.py
python3 tools/test_publish_update_catalog.py
```

For relevant changes, also run any new tests from tools/test_*.py and compare the CI workflow steps. Use explicit failure reporting if a dependency or tool is unavailable. Do not silently skip failing tests.

- Inspect changed files and full diff before committing and again before merging.
- Use `dart format` and `dart fix` in development only when required; **commit and review their edits** before rerunning the same non-mutating analyzer that release CI uses.
- Be alert that Dart analyzer may fail on informational lints, depending on CI configuration.
- Check test coverage for package import, data persistence and recovery, WebView JS bridge, APK version metadata, and SHA-256 download validation where affected.

## .chappy and ASMR smoke tests

- ZIP contains manifest.json and index.html at root, matching app ID/version and allowed permissions.
- Respect ZIP cap 12MiB, uncompressed cap 24MiB, 200 files, ASCII paths, and per-file cap 10MiB.
- Reject traversal, symlinks, untrusted external network/script dependencies, oversized and malformed packages.
- Confirm existing app ID/version updates keep saved user data. Keep the source HTML and original .chappy available for backup.
- On Android verify import from Chappy Player, launch, JS bridge, storage survival after restart; for ASMR, test audio start/stop, stereo behavior, effect controls and device-specific recording separately.
- Web/browser simulation is not proof of Android WebView or device audio correctness.

## Signed APK update checks

- Source repository: private `mibesamiti-png/chappy-player`; public signed-APK-only destination: `mibesamiti-png/chappy-player-updates`.
- Publication workflow: .github/workflows/publish-signed-apks.yml; manually triggered, only after the owner approves release.
- Same Android package ID, pinned certificate and signing key across all production versions.
- Flutter --split-per-abi Android versionCode uses the release build sequence plus: armeabi-v7a +1000, arm64-v8a +2000, x86_64 +4000. The update feed's cross-ABI buildNumber is not the installed ARM64 versionCode.
- The published release must contain the correct ABI APKs, SHA-256 digests, versionName/versionCode, and a matching update.json.
- Android updater must reject downgrade, wrong certificate, package mismatch, missing ABI, tampered artifact; it must hand off to Android's user-approved installer rather than silently installing.
- For Xiaomi 11T Pro (ARM64), back up JSON app data and .chappy files, use the **in-app update flow** without uninstalling, then confirm new app version, installed mini-apps, and saved ASMR/memo settings.
- Code merged and signed APK published are separate; do not announce the update as available until the release and feed exist.

## Deployment status report template

- Commit / PR:
- Implementation:
- Raw analyze / tests:
- CI link and exact conclusion:
- Signed release link (or not published):
- Real-device checks (completed / not done):
- Remaining blockers and user action:

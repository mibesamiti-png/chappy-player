---
name: chappy-player-dev
description: Develop, debug, review, package, test, and release the Chappy Player Flutter Android app and its .chappy mini-apps. Use for GitHub Actions failures, APK version/signature problems, CI parity, WebView/JavaScript bridge issues, Stable/Debug catalogs, Android file imports, and ASMR Sound Lab mini-app integration.
---

# Chappy Player development workflow

Use this repo-local skill when the user asks for Chappy Player changes or help diagnosing its builds. Keep steps proportional to the task. Load the linked references only for the relevant phase.

## 1. Establish ground truth

1. Read AGENTS.md, the target source/tests, relevant docs, and current PRs/Actions. Identify the exact commit SHA or branch being changed.
2. Distinguish source merged, CI succeeded, signed APK published, and Android device tested. These are **different** milestones.
3. Classify the change: Flutter/Dart UI, native Android host, offline .chappy content, CI/packaging, or signed release. Check its impact on existing saved data.
4. Do not invent successful tests, links, APK output paths, or release versions.

## 2. Implement safely

1. Work in a dedicated branch and scoped PR; do not edit the production release repository as a shortcut.
2. Read the entire affected code region before editing. Add focused regression tests for bug fixes.
3. Never derive an edit exclusively from a log line number, because formatting can move the code.
4. For programmatic text replacement, verify the old fragment occurs exactly once. Use a **replacement function** when a JavaScript replacement value contains dollar signs (especially dollar-quote). Do not interpret source text as a replacement template.
5. After every write, re-fetch the file, compare its full content with the intended result, inspect the changed diff, and confirm no duplicated, truncated, or unrelated lines. Serialize branch writes if uncertain.
6. Respect runtime restrictions: .chappy is an offline ZIP/HTML/JS app with strict limits; do not add unrestricted WebView network/native permissions without security review.

## 3. Run quality gates

1. Run raw, non-mutating `flutter analyze` and `flutter test` against the committed sources. Do not rely on uncommitted `dart fix --apply` or `dart format` in a CI job to mask a release failure.
2. Run applicable `node tools/test_bootstrap.js` and Python checks from `tools/test_*.py`; package/bridge/signing/update-feed changes require their corresponding checks.
3. If Flutter is not installed locally, check the GitHub Actions run for the **exact PR head SHA** and inspect failed job logs. Do not call a passing debug job equivalent to release if their steps differ.
4. Re-run tests after each fix. Inspect the *final* workflow status and never merge with failing or incomplete required checks.
5. Consult [quality and release checklist](references/quality-and-release.md) for commands and device checks.

## 4. APK release protection

1. Production workflow: .github/workflows/publish-signed-apks.yml. Its manual trigger and fixed signing key are intentional safety gates.
2. Release only on explicit user instruction. Ensure all test gates pass on the intended main commit, version increases, the signer is pinned, and each ABI's versionCode is greater than the installed value.
3. Never publish debug-signed APKs as production updates. Verify arm64-v8a, armeabi-v7a and x86_64 APK metadata, hashes, signature, and update.json before reporting success.
4. Do not uninstall or delete existing app data to recover from a failed update. Android still requires the user's install confirmation.
5. Keep APK Stable/Debug channel design separate from .chappy Stable/Debug catalog, and never claim the former has shipped until code, release, and device testing confirm it.

## 5. Debugging and progress reporting

1. Fetch the specific failed Actions run → failed job → step logs. Identify primary errors before cascade errors.
2. Patch the *cause*, not only a symptom. Add a regression check when possible.
3. Maintain explicit status: implemented / partial / missing / fix needed; and code inspection / CI tested / real device untested.
4. Explain what the user must do next in concrete terms. Keep private files, secrets, and personal data out of public repositories.
5. Read [incident prevention](references/incident-prevention.md) when fixing repeated CI, text-editing, or release mistakes.

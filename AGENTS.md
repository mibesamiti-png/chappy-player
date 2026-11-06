# Chappy Player — agent instructions

This public source repository is the source of truth for Chappy Player (Flutter/Android) and the offline .chappy mini-app runtime. The source and existing commit history are public; do not put secrets, user backups, logs containing personal information or signing materials in tracked files, PRs or issues.

## Before changing code

- Read the relevant source files, tests, README, and docs. Check the latest main/PR state and current release status; do not infer that a merged PR has reached a published APK.
- For implementation, debugging, CI, mini-app packaging, or release tasks, follow the repo-local skill: .agents/skills/chappy-player-dev/SKILL.md.
- Make scoped changes on a branch and open a PR. Keep unrelated feature and release changes separate.
- Preserve installed app data, app package ID, signature continuity, rollback safeguards, and per-ABI Android versionCode checks.
- Never reveal, embed, regenerate, or print keystores, passwords, signing fingerprints used as secrets, or release tokens. Signing configuration stays in GitHub Secrets/Variables.
- Do not turn off validation, sign with a new key, force an Android downgrade, auto-uninstall, or publish a production APK to make a test pass.
- Do not treat a .chappy payload as a trusted Android APK. Public third-party content needs separate security review.

## Definition of done

- Read back every written file and verify the intended full content, especially after scripted replacement. Inspect the diff; do not rely on path/line numbers alone.
- Prefer direct syntax-safe edits. When using JavaScript String.replace, use a replacement callback for text containing dollar signs; a replacement string interprets special dollar sequences.
- Run or check the *same* unmodified source through flutter analyze and flutter test as the signed-release pipeline. The debug CI must not hide problems with uncommitted dart fix/format changes.
- Execute applicable bridge, packaging, update feed, and release-safety tests. If the local Flutter SDK is unavailable, verify a GitHub Actions run against the exact commit SHA and say which checks could not be run.
- Do not merge a failing PR, assume a queued CI has passed, or claim Android real-device validation based on CI alone.
- Signed APK publication requires an explicit user request, successful pre-release checks, and correct published artifacts. Keep the Publish Signed APK Updates workflow manual unless the owner explicitly changes the policy.
- Report separately: implemented, code checks passed/failed, APK published/unpublished, real-device tested/untested.

## Key references

- Skill: .agents/skills/chappy-player-dev/SKILL.md
- Quality checklist: .agents/skills/chappy-player-dev/references/quality-and-release.md
- Failure prevention: .agents/skills/chappy-player-dev/references/incident-prevention.md
- Android upgrade test: docs/android-update-smoke-test.md
- App catalog: docs/chappy-apps-catalog.md

# Chappy Player CI: Quick checks + on-demand Debug APK

## Policy (2026-11-08)

Day-to-day development prioritizes short feedback cycles. A **Debug build is a test artifact**, not the user-approved signed Stable release. Building it for every small PR is unnecessary. However, source-level tests do not prove that an APK installs and works on hardware.

| Event | Quick CI | Full Android Debug APK |
| --- | --- | --- |
| PR opened/updated | Automatic | Not automatic |
| Commit to main | Automatic | Not automatic |
| Milestone / real-device debugging | Available manually | Run manually |
| Native bridge / Gradle / Android permission changes | Automatic | Run manually before relying on Android behavior |
| Signed Stable publication | Independent signed-release workflow and release checklist | Do not substitute Debug for Stable |

## Actions

- `Quick CI` (`.github/workflows/quick-ci.yml`): auto on PR and main push, and manual dispatch; Flutter analyze, Flutter unit tests, and selected security/native contract + JS checks, but no APK, signing, or artifact upload.
- `Build Android APK` (`.github/workflows/build-android.yml`): **workflow_dispatch only**; preserves the previous comprehensive steps, sample packaging, native contracts, debug variant separation, `flutter build apk --debug`, and artifact upload.
- Existing `Publish Signed APK Updates` and signing secrets are **untouched**. Do not trigger them without deliberate signed-release approval.

## When to run a Debug APK

Use Actions → **Build Android APK** → **Run workflow**, choose the desired branch/commit, and download the Debug artifact after success. Prefer one run per feature batch, not every small fix. For authentication, Android platform changes, permissions, file I/O, bridge changes, and app updates, request a Debug build plus targeted device smoke tests before calling the functionality verified. Stable publication retains its separate gates.

## Migration caveats

- Prior branch protection rules or automation that requires the old `Build Android APK / test-build` PR status may need a manual administrator update to **`Quick CI / test-build`**. Until that is done GitHub may block merges; never disable safety protections blindly.
- This PR alters CI, so inspect the actual new Quick CI result and its summary before merging. GitHub workflows can behave differently on PR events versus manual dispatch.
- The Quick CI selection intentionally excludes APK packaging, APK signing, release deployment, and package-dependent smoke tests. These remain covered by full Debug/Stable workflows. **Quick CI PASS is not proof of APK build or real-device success.**
- Keep a record of the exact commit or PR head used to create each Debug APK; source may have advanced after an artifact was built.

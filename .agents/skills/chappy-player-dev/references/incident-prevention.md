# Incident prevention (2026-11-04 / 2026-11-05)

Use these concrete failure modes to avoid repeated mistakes. This is a diagnostic reference, not proof that a specific fix has already passed CI.

## 1. Debug CI passed but production analyze failed

- The debug workflow previously ran `dart fix --apply` and `dart format lib test` before `flutter analyze`; the signed-release workflow checked unmodified source.
- A manual signed release failed on `curly_braces_in_flow_control_structures` despite earlier debug CI being green.
- Prevention: check both workflows against the same committed source; require raw `flutter analyze` and `flutter test` before announcing readiness. Do not paper over a release gate with CI-only mutation.

## 2. Line-number-only fixes were incomplete

- Lint line numbers changed after formatting, and the first follow-up patch left two multiline guards untouched.
- Prevention: inspect the full source expressions and diff; search by exact syntax and verify every intended guard, rather than blindly editing the number shown by old logs.

## 3. JavaScript replacement strings can corrupt source containing dollar signs

- When a JS `String.replace(search, replacementString)` replacement contains a dollar-quote sequence, JavaScript expands that as **the suffix of the original input**. A Dart regular expression ending with a dollar anchor next to a quote can accidentally trigger this.
- A prior attempted fix produced truncated Dart and duplicated method definitions even though an edit API returned success.
- Prevention: use `source.replace(needle, () => replacement)` or a clearly reviewed AST edit; verify an exact single match, then re-fetch the entire GitHub file and compare to the expected content.
- Do not commit or merge if file length, number of class/method definitions, or diff is unexpectedly changed.

## 4. Never equate success at different stages

- PR open ≠ merged; merge ≠ successful CI; successful CI ≠ published signed APK; installed APK ≠ tested all device features.
- If a signed release fails before APK publication, report that the old release remains current. Do not ask the user to uninstall or change signing keys.

## 5. Recovery for a failed job

1. Fetch the run, job steps, and logs for the **exact commit**.
2. Identify the *earliest* real error; subsequent compiler errors may be cascading effects.
3. Read actual source around the failing syntax and compare with a known-good version.
4. Apply a minimal fix and read back the complete resulting file.
5. Inspect the diff, rerun CI, and only then merge/release with user authorization.

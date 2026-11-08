# Chappy Player R3 — Device Lab + File Lab combined batch

## Goal

Improve safety and debug usefulness across two existing local mini-apps, without modifying the host native bridge or adding permissions. All device and file operations remain **explicit user actions**. Debug APK remains an on-demand milestone artifact, separate from the signed Stable release.

## Device Lab (4 related improvements)

1. User-triggered capability summary showing the number of available sensors and haptic support; **never auto-probe hardware**.
2. Reject missing, malformed and non-finite XYZ readings instead of displaying `NaN` or moving the tilt indicator to invalid coordinates.
3. Use a generation token to ignore late gravity samples after stop, backgrounding or a new session.
4. Remove raw host exception details from sensor/haptic status messages, which can contain private paths and device information.

## File Lab (5 related improvements)

5. Validate text filename and allowed extensions (`txt/json/csv/md`) before Android save or local draft save; reject path separators, control characters, and invalid length.
6. Check UTF-8 content size against 64KiB before the bridge is called, and refuse an oversized selected text document.
7. Validate an untrusted locally saved draft before restoring it into the editor; reject invalid names and oversized drafts.
8. Hide raw exceptions in user-visible file-operation and transfer-cancel errors. Avoid overlapping independent operations while a binary transfer is running.
9. Clamp untrusted native transfer byte counts and progress percentages before displaying them.

## Regression tests

- `node tools/test_device_lab.js` covers user-only feature probing, sensor availability, haptic calls, invalid XYZ, stale callbacks and redacted host errors.
- `node tools/test_file_lab.js` covers filename and UTF-8 bounds, corrupt draft rejection, native error redaction, transfer operation locking, progress bounds and existing asset import/export, compressed ZIP, cancel and delete flows.
- Quick CI also runs all Flutter analyses/tests and source-level security contracts.

No claim of real Android hardware testing, actual sensor accuracy, or file-system behavior in this batch. No automatic APK or signed release was triggered.

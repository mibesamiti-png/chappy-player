# PC Link batch R1: live stage, safe cancellation, regression coverage

This batch improves the *existing* Android PC confirmation screen without changing the QR-v3 wire protocol, cryptographic verification, permissions, stored history, or Windows companion implementation.

## Included tasks

1. Show the current safe, fixed-name stage below the progress indicator while a pairing attempt is active (`pair_progress_stage`).
2. Differentiate local QR eligibility, Android KeyStore identity preflight, LAN/TLS, PC signature, Android consent/signature and final PC approval as stages are reached.
3. Remove live stage immediately on completion, classified failure, explicit cancellation and application backgrounding. An in-flight callback from an older generation cannot replace the current UI state.
4. Update the waiting text to describe both PC approval and the possible Android signing dialog instead of claiming the PC always requires typing YES.
5. Add widget tests for waiting on a native LAN eligibility check, denying that check, cancelling with a late result, and backgrounding with a late result.

The progress stage indicates **the last attempted operation**, not a quantitative percent, authentication success or the definitive root cause. It is only displayed during an active attempt and never written to disk, copied to the diagnostic report, transmitted over the network, or surfaced to mini-app JavaScript. The existing fail-closed QR consumption and explicit consent rules remain.

## Verification

Quick CI: Flutter analysis, complete Flutter unit/widget tests, network/Windows bridge contract smoke tests. Run a single Debug APK build when a feature batch is ready for Android↔Windows real-device QA; that physical validation is still outstanding. Signed Stable publishing is separate and unchanged.

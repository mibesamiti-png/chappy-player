# Game Server Lab R2: Network + mini-app UI batch

This batch upgrades the **existing** Chappy Game Server Lab sample mini-app. It does not change the Android native network bridge or permit any new endpoint, network protocol, permission, persistent pairing, or automatic send.

## Implemented tasks

1. **WSS traffic summary:** local, non-persistent counters for successful text sends, received messages, and dropped messages. Cleared only when the app is reloaded, not each disconnect.
2. **Connection-aware buttons:** disable normal send and gravity-sensor send while disconnected; re-enable after an explicitly approved WSS connection.
3. **HTTPS progress and response state:** visible independent HTTPS GET/POST status, including HTTP status, without confusing WSS connection state.
4. **JSON preflight:** POST only accepts JSON objects; invalid input or more than 8192 UTF-8 bytes is rejected before calling the network bridge.
5. **HTTPS overlap guard:** one GET/POST at a time, disabling both buttons while busy.
6. **HTTPS timeout:** 30-second request watchdog; the screen reports failure and removes the timer, without silently claiming success.
7. **Privacy-preserving connection logs:** do not echo user-entered WSS URL, connection origin, or raw host exceptions in logs. Receive messages remain visible as the user-requested protocol test output; avoid sending secrets to external servers.

## Tests

`node tools/test_game_server_lab.js` verifies transport method separation, WSS counters, drop counter, connection-aware send controls, sensor/haptic operations, invalid/oversize JSON rejection, overlapping HTTPS requests, HTTP status, safe error logging, manual-only networking, automatic close on background, and the WSS watchdog.

`Quick CI` also runs Flutter analyze/tests and native security contracts. Debug APK remains a manually triggered milestone build; device/real-server behavior is **not verified** by this PR. Signed Stable publishing is untouched.

## Notes

- HTTPS failure may leave a native request in flight; the UI does not claim that aborting the local watchdog cancels the OS request. An in-flight HTTPS request does not initiate any subsequent action.
- The feature is a user-controlled diagnostic mini-app, not an automated remote-control client. Never send sensitive information to public echo services.

# Chappy Hub Mobile — Android Handoff R1 (v0.2.0)

## Scope and priority
- Priority is ③ local Android handoff, then ② PC Link, and ① OpenAI API **last**.
- Windows Chappy Hub remains owned by its separate team and is not modified.
- The companion mini-app keeps `id: local.chappy.hubmobile` and the existing `hubmobile-data-v2` storage key.
- Public Debug mini-app catalog is `mibesamiti-png/chappy-apps`. Stable app catalog and signed player releases must remain unchanged until separately approved.

## Native commands (Android Debug player host)
The Chappy Player host exposes `Chappy.handoff.copyPrompt(text)`, `sharePrompt(text)`, `openChatGPT()` through its local WebView bridge. Each call:

1. Requires the requesting .chappy ID to be exactly `local.chappy.hubmobile`, an active foreground route and no concurrent handoff.
2. Requires the user to approve a Flutter dialog first, with an abbreviated prompt preview for the text methods.
3. Validates prompt length 1–5000 UTF-16 code units; blank input is rejected.
4. For copy, invokes the Android clipboard with the original prompt.
5. For share, invokes Android ACTION_SEND text/plain via Sharesheet (user selects recipient; no programmatic recipient).
6. For open, invokes ACTION_VIEW on `https://chatgpt.com/` (Android chooses app/browser).
7. Returns a status (`copied`, `chooser_opened`, `external_app_opened`, `cancelled`) **not** a delivery or completion acknowledgement.

The .chappy mini-app must **never** interpret `chooser_opened` as sent. Only the user's explicit `手動で送信した` action moves from AWAIT_SEND to AWAIT_RESULT. Only explicit `回答を確認した` moves to the next step. Paused/stopped flows never handoff.

## Security and privacy
- No AccessibilityService, read/inspect other applications, web scraping, auto-submission or extraction of ChatGPT Output. OpenAI policies and Android platform rules constrain this approach.
- No broad launcher, arbitrary URL, arbitrary package name, or unrestricted external intent in the mini-app API.
- No prompt text in logs or catalog; errors carry generic strings only.
- Empty/min-length/oversized text rejected, operation re-entry denied.
- No background launch, persistent overlay, notification or new Android permission.
- The mini-app is compatible with older players for offline management only. Android handoff buttons clearly report that a newer Debug host is needed.
- Opening a sharing chooser or browser proves only that Android accepted the operation; it does not prove sending, reading, ChatGPT app availability or a response.

## Quality and release gates
- Dart unit test `test/miniapp_handoff_policy_test.dart` covers exact app ID and prompt validation.
- Node JS bridge test `tools/test_bootstrap.js` verifies method names, payloads and callback responses.
- Mini-app `node test_engine.js` and `node --check main.js`; .chappy ZIP with manifest/index at root and ASCII paths.
- CI must validate Flutter analyzer/tests and Android compile against exact PR HEAD. Android physical QA is separate and pending.
- The signed release workflow remains manual: **do not publish a production APK** without explicit user instruction.

## Device QA (pending)
1. Install a fresh Android Debug APK built from this PR, preserving signed-release data.
2. In Player open Chappy Apps > Debug > refresh > Chappy Hub Mobile v0.2.0.
3. Create a session, select a prompt and tap copy: approve, verify Android clipboard, and ensure run remains AWAIT_SEND.
4. Tap Android share: verify chooser, cancel and retry; ensure no auto advance.
5. Tap ChatGPT open: verify external browser/app selection; return to Player, confirm persisted active run.
6. Click manually sent, then result checked, verify advance; test pause/resume/stop, rotation, background, cold launch.
7. Try old Player: handoff must show informative unsupported-host error; offline queue should still function.
8. Confirm no permission prompt for accessibility and no sensitive prompt contents in the Player diagnostic log.

## Deployment state
- Host source and Debug mini-app may pass CI independently.
- Installing the .chappy package **does not install new host API**; a compatible Debug Player APK is needed for the new buttons.
- Android on-device success is not claimed by PR/CI alone.
